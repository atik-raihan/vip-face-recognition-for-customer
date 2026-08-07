import io
import base64
import matplotlib
matplotlib.use('Agg')  # non-interactive backend
import matplotlib.pyplot as plt


def chart_to_base64(labels, total_data, vip_data, title, chart_type='bar'):
    """
    Generate a chart and return it as a base64-encoded PNG string.
    """
    if not labels or not total_data:
        return None

    fig, ax = plt.subplots(figsize=(6, 3.5), dpi=100)
    
    x = range(len(labels))
    width = 0.35
    
    if chart_type == 'bar':
        bars1 = ax.bar([i - width/2 for i in x], total_data, width, 
                       label='Total', color='#007bff', alpha=0.8)
        bars2 = ax.bar([i + width/2 for i in x], vip_data, width, 
                       label='VIP', color='#ffc107', alpha=0.8)
    else:  # line
        ax.plot(labels, total_data, marker='o', label='Total', 
                color='#007bff', linewidth=2)
        ax.plot(labels, vip_data, marker='o', label='VIP', 
                color='#ffc107', linewidth=2)
        ax.fill_between(labels, total_data, alpha=0.1, color='#007bff')
        ax.fill_between(labels, vip_data, alpha=0.1, color='#ffc107')

    ax.set_title(title, fontsize=12, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=30, ha='right', fontsize=9)
    ax.legend(loc='upper right', fontsize=9)
    ax.set_ylabel('Visits', fontsize=10)
    ax.grid(axis='y', alpha=0.3)
    
    # Ensure y-axis starts at 0 and uses integers
    ax.set_ylim(bottom=0)
    from matplotlib.ticker import MaxNLocator
    ax.yaxis.set_major_locator(MaxNLocator(integer=True))

    plt.tight_layout()
    
    buf = io.BytesIO()
    fig.savefig(buf, format='png', bbox_inches='tight')
    buf.seek(0)
    img_base64 = base64.b64encode(buf.read()).decode('utf-8')
    plt.close(fig)
    
    return f"data:image/png;base64,{img_base64}"