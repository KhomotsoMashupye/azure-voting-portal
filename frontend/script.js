// script.js

let selectedCandidate = null;


const API_URL = window.location.hostname === 'localhost'
    ? 'http://localhost:3000/api/vote'  
    : '/api/vote';                     

function selectCandidate(element, name) {
    // Remove selected class from all candidates
    document.querySelectorAll('.candidate-option').forEach(el => {
        el.classList.remove('selected');
    });

    // Add selected class to current candidate
    element.classList.add('selected');
    selectedCandidate = name;

    // Enable the submit button
    document.getElementById('submit-btn').disabled = false;
}

async function castVote() {
    const btn = document.getElementById('submit-btn');
    const status = document.getElementById('status-msg');

    // Disable button to prevent multiple clicks
    btn.disabled = true;
    status.style.color = "#64748b";
    status.innerText = "Encrypting and submitting ballot...";

    try {
        const response = await fetch(API_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ candidate: selectedCandidate })
        });

        if (response.ok) {
            status.style.color = "#10b981";
            status.innerText = "Success! Your vote has been recorded.";
        } else {
            const errData = await response.json();
            status.style.color = "#ef4444";
            status.innerText = `Submission failed: ${errData.error || 'Unknown error'}`;
            btn.disabled = false;
        }
    } catch (err) {
        status.style.color = "#ef4444";
        status.innerText = "Submission failed. Please check your connection and try again.";
        btn.disabled = false;
    }
}