Write-Host "VIP POPUP FIX SCRIPT STARTED" -ForegroundColor Cyan

$ErrorActionPreference = "Stop"

$root = (Get-Location).Path

$viewsFile = Join-Path $root "face_recognition_app\views.py"
$posFile   = Join-Path $root "templates\sales\pos.html"

Write-Host "Checking files..." -ForegroundColor Yellow

if (-not (Test-Path $viewsFile)) {
    throw "views.py not found: $viewsFile"
}

if (-not (Test-Path $posFile)) {
    throw "POS template not found: $posFile"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"

Copy-Item $viewsFile "$viewsFile.backup_$stamp" -Force
Copy-Item $posFile "$posFile.backup_$stamp" -Force

Write-Host "[PASS] Backups created" -ForegroundColor Green

$posText = Get-Content $posFile -Raw

$start = "<!-- VIP_AUTO_RECOGNITION_START -->"
$end   = "<!-- VIP_AUTO_RECOGNITION_END -->"

$pattern = "(?s)" + [regex]::Escape($start) + ".*?" + [regex]::Escape($end)

$posText = [regex]::Replace($posText, $pattern, "")

$block = @"
<!-- VIP_AUTO_RECOGNITION_START -->

<div id="vipAutoRecognitionPopup"
     style="
     display:none;
     position:fixed;
     z-index:99999;
     right:25px;
     bottom:25px;
     width:390px;
     max-width:calc(100vw - 30px);
     background:#fff;
     border:3px solid #ffc107;
     border-radius:18px;
     box-shadow:0 15px 45px rgba(0,0,0,.30);
     overflow:hidden;
     ">

    <button
        type="button"
        onclick="closeVipAutoPopup()"
        style="
        position:absolute;
        right:10px;
        top:5px;
        border:0;
        background:transparent;
        font-size:28px;
        cursor:pointer;
        z-index:2;
        ">
        &times;
    </button>

    <div style="
         background:linear-gradient(135deg,#ffc107,#ff9800);
         padding:15px;
         font-size:20px;
         font-weight:bold;">
        ⭐ VIP CUSTOMER DETECTED
    </div>

    <div style="padding:20px;">

        <div style="
             font-size:26px;
             font-weight:bold;
             margin-bottom:10px;"
             id="vipAutoCustomerName">
            VIP Customer
        </div>

        <div style="
             display:inline-block;
             background:#ffc107;
             padding:5px 12px;
             border-radius:20px;
             font-weight:bold;
             margin-bottom:15px;">
            VIP CUSTOMER
        </div>

        <p>
            <strong>Purchase:</strong>
            BDT <span id="vipAutoPurchase">0</span>
        </p>

        <p>
            <strong>Confidence:</strong>
            <span id="vipAutoConfidence">0%</span>
        </p>

        <p>
            <strong>Phone:</strong>
            <span id="vipAutoPhone">-</span>
        </p>

        <p style="color:#777;">
            Customer recognized automatically by the live camera.
        </p>

    </div>
</div>

<script>
(function () {

    let lastRecognitionId = 0;
    let popupTimer = null;
    let checking = false;

    function closeVipAutoPopup() {

        const popup =
            document.getElementById(
                "vipAutoRecognitionPopup"
            );

        if (popup) {
            popup.style.display = "none";
        }

        if (popupTimer) {
            clearTimeout(popupTimer);
            popupTimer = null;
        }
    }

    window.closeVipAutoPopup = closeVipAutoPopup;

    function showVipPopup(data) {

        const popup =
            document.getElementById(
                "vipAutoRecognitionPopup"
            );

        if (!popup) {
            return;
        }

        const name =
            document.getElementById(
                "vipAutoCustomerName"
            );

        const purchase =
            document.getElementById(
                "vipAutoPurchase"
            );

        const confidence =
            document.getElementById(
                "vipAutoConfidence"
            );

        const phone =
            document.getElementById(
                "vipAutoPhone"
            );

        if (name) {
            name.textContent =
                data.customer_name ||
                "VIP Customer";
        }

        if (purchase) {
            purchase.textContent =
                data.total_purchase || "0";
        }

        if (phone) {
            phone.textContent =
                data.phone || "-";
        }

        if (confidence) {

            let value =
                Number(data.confidence || 0);

            if (value <= 1) {
                value *= 100;
            }

            confidence.textContent =
                value.toFixed(1) + "%";
        }

        popup.style.display = "block";

        if (popupTimer) {
            clearTimeout(popupTimer);
        }

        popupTimer = setTimeout(
            closeVipAutoPopup,
            10000
        );
    }

    async function checkRecognition() {

        if (checking) {
            return;
        }

        checking = true;

        try {

            let url =
                "/camera/latest-recognition/";

            if (lastRecognitionId > 0) {

                url +=
                    "?since_id=" +
                    encodeURIComponent(
                        lastRecognitionId
                    );
            }

            const response =
                await fetch(
                    url,
                    {
                        cache:"no-store",
                        credentials:"same-origin",
                        headers:{
                            "X-Requested-With":
                                "XMLHttpRequest"
                        }
                    }
                );

            if (!response.ok) {
                return;
            }

            const data =
                await response.json();

            if (!data.new) {
                return;
            }

            const recognitionId =
                Number(data.log_id || 0);

            if (
                recognitionId > 0 &&
                recognitionId <= lastRecognitionId
            ) {
                return;
            }

            if (recognitionId > 0) {
                lastRecognitionId =
                    recognitionId;
            }

            console.log(
                "VIP recognition:",
                data
            );

            if (
                data.is_vip === true ||
                data.is_vip === "true" ||
                data.is_vip === 1
            ) {
                showVipPopup(data);
            }

        }
        catch (error) {

            console.debug(
                "Recognition polling:",
                error
            );

        }
        finally {

            checking = false;

        }
    }

    function startVipRecognition() {

        checkRecognition();

        setInterval(
            checkRecognition,
            1500
        );
    }

    if (
        document.readyState ===
        "loading"
    ) {

        document.addEventListener(
            "DOMContentLoaded",
            startVipRecognition
        );

    }
    else {

        startVipRecognition();

    }

})();
</script>

<!-- VIP_AUTO_RECOGNITION_END -->
"@

if ($posText -match "{%\s*endblock\s*%}") {

    $posText = [regex]::Replace(
        $posText,
        "{%\s*endblock\s*%}",
        "`r`n$block`r`n`r`n{% endblock %}",
        1
    )

}
else {

    $posText += "`r`n$block`r`n"

}

Set-Content $posFile $posText -Encoding UTF8

Write-Host "[PASS] VIP popup installed" -ForegroundColor Green

python manage.py check

if ($LASTEXITCODE -ne 0) {
    throw "Django check failed."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " VIP POPUP FIX COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Restart Django, then open /pos/." -ForegroundColor Cyan
