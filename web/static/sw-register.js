// Registers the service worker. Kept out of index.html so the page needs no inline script
// (the server's Content-Security-Policy only allows script files from this server).
if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => {
        navigator.serviceWorker
            .register("static/sw.js")
            .then(() => console.log("ServiceWorker registration successful"))
            .catch((err) => console.log("ServiceWorker registration failed: ", err));
    });
}
