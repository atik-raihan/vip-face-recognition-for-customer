let faceLocked = false;
let countdownRunning = false;
let countdown = 3;
let captureReady = false;

const statusText = document.getElementById("status");
const countdownBox = document.getElementById("countdown");
const saveButton = document.getElementById("save-btn");
const capturedImage = document.getElementById("captured-image");
const cameraStream = document.getElementById("camera-stream");

function setStatus(message, cssClass=""){

    statusText.className="";

    if(cssClass){
        statusText.classList.add(cssClass);
    }

    statusText.innerText=message;

}

async function pollFaceStatus(){

    if(faceLocked){
        return;
    }

    try{

        const response=await fetch("/camera/registration/status/");

        const data=await response.json();

        if(data.status==="waiting"){

            setStatus("Looking for a face...");

            stopCountdown();

        }

        else if(data.status==="multiple"){

            setStatus(
                "Multiple faces detected",
                "warning-message"
            );

            stopCountdown();

        }

        else if(data.status==="face_found"){

            setStatus(
                "? Face Found",
                "success-message"
            );

            startCountdown();

        }

    }

    catch(e){

        console.log(e);

    }

}

function startCountdown(){

    if(countdownRunning){
        return;
    }

    countdownRunning=true;

    countdown=3;

    countdownBox.style.display="flex";

    const timer=setInterval(()=>{

        countdownBox.innerHTML=countdown;

        countdown--;

        if(countdown<0){

            clearInterval(timer);

            capture();

        }

    },1000);

}

function stopCountdown(){

    countdownRunning=false;

    countdownBox.style.display="none";

    countdown=3;

}

async function capture(){

    countdownBox.style.display="none";

    faceLocked=true;

    setStatus("Capturing...","success-message");

    try{

        const response=await fetch(
            "/camera/registration/capture/"
        );

        const data=await response.json();

        if(data.success){

            capturedImage.src=data.image;

            capturedImage.style.display="block";

            cameraStream.style.display="none";

            saveButton.disabled=false;

            captureReady=true;

            setStatus(
                "? Captured Successfully",
                "success-message"
            );

        }

        else{

            resetCapture();

        }

    }

    catch(e){

        console.log(e);

        resetCapture();

    }

}

function resetCapture(){

    faceLocked=false;

    captureReady=false;

    cameraStream.style.display="block";

    capturedImage.style.display="none";

    saveButton.disabled=true;

    setStatus("Looking for a face...");

}

setInterval(

    pollFaceStatus,

    500

);
