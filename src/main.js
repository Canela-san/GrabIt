const button = document.createElement("div");
const t = document.createTextNode("Grab");

button.appendChild(t);

// Styling: 
button.style.position = "fixed";
button.style.zIndex = "1000000000000000";
button.style.color = "#111111";
button.style.display = "flex";
button.style.justifyContent = "center";
button.style.alignItems = "center";
button.style.cursor = "pointer";
button.style.display = "flex";
button.style.backgroundColor = "#acf5d6"
button.style.bottom = "40px";
button.style.left = "-10px";
button.style.height = "40px"
button.style.width = "80px"
button.style.border = "none";
button.style.borderRadius = "0 20px 20px 0";

// functionality
button.onclick = () => {
    console.log("GRABBED!");
}

document.body.appendChild(button)