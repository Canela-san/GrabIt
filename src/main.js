const css = `
    #grabit-button {
        position: fixed;
        z-index: 100000000000000;
        color: #111111;
        padding-left: 10px;
        cursor: pointer;
        display: flex;
        background-color: #acf5d6;
        bottom: 40px;
        left: 0px;
        height: 60px;
        width: 90px;
        border: none;
        border-radius: 0 30px 30px 0;
        transform: translateX(-70px);
        transition: 500ms;
    }
        
    #grabit-button:hover {
        transform: translateX(0px);
    }

    #grabit-img {
        height: 100%;
    }
`

// Create a style tag
const style = document.createElement('style')
style.appendChild(document.createTextNode(css))

// Create the button element
const button = document.createElement("div")
const img = document.createElement("img")
img.id = "grabit-img"
img.src = browser.runtime.getURL('/assets/images/icon.png');
button.id = 'grabit-button'
button.appendChild(img);

// functionality
button.onclick = () => {
    console.log("GRABBED!")
}

// Append the style tag to the head of the document
document.head.appendChild(style)
// Append the button to the body of the document
document.body.appendChild(button)
