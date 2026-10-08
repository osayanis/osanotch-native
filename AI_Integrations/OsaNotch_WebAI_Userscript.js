// ==UserScript==
// @name         OsaNotch Universal AI Notifier
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Envoie une notification au Notch quand une IA Web a terminé de générer.
// @match        https://claude.ai/*
// @match        https://chatgpt.com/*
// @match        https://gemini.google.com/*
// @grant        GM_xmlhttpRequest
// ==/UserScript==

(function() {
    'use strict';

    let isGenerating = false;
    let aiName = window.location.hostname.includes("claude") ? "Claude Web" :
                 window.location.hostname.includes("chatgpt") ? "ChatGPT" : "Gemini";

    function notifyNotch(msg) {
        GM_xmlhttpRequest({
            method: "POST",
            url: "http://localhost:8081/notify",
            data: JSON.stringify({ msg: msg }),
            headers: { "Content-Type": "text/plain" }
        });
    }

    // Heuristique simple: on observe les changements dans le DOM pour trouver un bouton "Stop generating"
    const observer = new MutationObserver(() => {
        const bodyText = document.body.innerText.toLowerCase();
        const currentlyGenerating = bodyText.includes("stop generating") || bodyText.includes("arrête") || bodyText.includes("stop response");

        if (currentlyGenerating && !isGenerating) {
            isGenerating = true;
        } else if (!currentlyGenerating && isGenerating) {
            isGenerating = false;
            // Un délai pour s'assurer que c'est bien la fin
            setTimeout(() => notifyNotch(`${aiName} a fini de répondre !`), 1000);
        }
    });

    observer.observe(document.body, { childList: true, subtree: true, characterData: true });
})();
