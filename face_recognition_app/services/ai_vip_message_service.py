"""
NEW FILE.

Generates a short, personalized heads-up message for the STORE MANAGER
(not the customer) when a VIP is recognized -- e.g. "Regular VIP Jane Doe
just walked in, BDT 42,000 lifetime spend, last visited 12 days ago --
consider mentioning the new arrivals she asked about last time." The
manager reads this and decides how to greet the customer; nothing is ever
auto-sent to the customer.

Requires in settings.py:
    ANTHROPIC_API_KEY = "sk-ant-..."          # required
    ANTHROPIC_MODEL = "claude-sonnet-4-5"      # optional, has a default below

If the API call fails for any reason (no key set, network issue, rate
limit), this falls back to a plain template message rather than blocking
the WhatsApp notification entirely -- the manager should never miss a VIP
arrival just because the AI call had a bad moment.
"""
import logging

from django.conf import settings

logger = logging.getLogger(__name__)

DEFAULT_MODEL = "claude-sonnet-4-5"  # check docs.claude.com for current model names if this 404s


def _fallback_message(customer):
    return (
        f"VIP arrival: {customer.name} just walked in. "
        f"Total purchase: {customer.total_purchase}."
    )


def generate_vip_arrival_message(customer, confidence=None, recent_logs=None):
    """
    customer: the Customer model instance (must have .name, .total_purchase;
              other fields used opportunistically if present).
    confidence: optional float, the recognition confidence score.
    recent_logs: optional queryset/list of the customer's recent
                 RecognitionLog entries, most recent first, for visit
                 frequency context. Pass None to skip that context.

    Returns a plain string ready to send as-is over WhatsApp.
    """
    api_key = getattr(settings, "ANTHROPIC_API_KEY", None)
    if not api_key:
        logger.warning("ANTHROPIC_API_KEY not set -- using fallback VIP message.")
        return _fallback_message(customer)

    try:
        import anthropic

        client = anthropic.Anthropic(api_key=api_key)
        model = getattr(settings, "ANTHROPIC_MODEL", DEFAULT_MODEL)

        visit_context = ""
        if recent_logs:
            last_visit = recent_logs[0].recognized_at if len(recent_logs) > 0 else None
            visit_count = len(recent_logs)
            if last_visit:
                visit_context = f" They've visited {visit_count} times recently, last on {last_visit:%Y-%m-%d}."

        prompt = (
            f"A VIP customer named {customer.name} just walked into the store. "
            f"Their lifetime purchase total is {customer.total_purchase}."
            f"{visit_context}"
            f"{f' Recognition confidence: {confidence:.0%}.' if confidence else ''}\n\n"
            "Write a ONE-sentence, casual heads-up for the store manager's phone "
            "(WhatsApp), so they can greet this customer well. No greeting like "
            "'Hi manager', no markdown, no quotes around it -- just the sentence itself. "
            "Do not invent specific products or facts not given above."
        )

        response = client.messages.create(
            model=model,
            max_tokens=120,
            messages=[{"role": "user", "content": prompt}],
        )

        text = "".join(
            block.text for block in response.content if getattr(block, "type", None) == "text"
        ).strip()

        return text if text else _fallback_message(customer)

    except Exception as exc:
        logger.warning(f"AI VIP message generation failed, using fallback: {exc}")
        return _fallback_message(customer)

