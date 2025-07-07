// Simple JavaScript Hello World Program

// Console version
console.log("Hello, World!");

// Function version
function sayHello() {
    return "Hello, World!";
}

// Call the function and log the result
console.log(sayHello());

// For browser environment - check if document exists
if (typeof document !== 'undefined') {
    // Wait for DOM to be ready
    document.addEventListener('DOMContentLoaded', function() {
        // Create and append hello message to body
        const helloElement = document.createElement('h1');
        helloElement.textContent = "Hello, World!";
        helloElement.style.textAlign = 'center';
        helloElement.style.color = '#333';
        helloElement.style.fontFamily = 'Arial, sans-serif';
        document.body.appendChild(helloElement);
        
        // Also log to browser console
        console.log("Hello, World! (from browser)");
    });
}
