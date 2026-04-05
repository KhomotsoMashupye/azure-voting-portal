const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const { ServiceBusClient } = require("@azure/service-bus");

const app = express();
app.use(cors());
app.use(express.json());


const pool = new Pool({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: 'election_db',
    port: 5432,
    ssl: { rejectUnauthorized: false } 
});



const sbClient = new ServiceBusClient(process.env.SERVICE_BUS_CONNECTION_STRING);
const sender = sbClient.createSender("vote-queue");

app.post('/api/vote', async (req, res) => {
    const { candidate, voterId } = req.body;

    if (!candidate || !voterId) {
        return res.status(400).json({ error: "Missing candidate or voter ID" });
    }

    try {
        
        const checkVote = await pool.query('SELECT id FROM votes WHERE voter_id = $1', [voterId]);
        if (checkVote.rows.length > 0) {
            return res.status(403).json({ error: "Voter has already cast a ballot." });
        }

        
        const message = {
            body: {
                candidate: candidate,
                voterId: voterId,
                timestamp: new Date().toISOString()
            },
            contentType: "application/json",
            label: "Election2026"
        };

        
        await sender.sendMessages(message);

        console.log(`Vote for ${candidate} queued successfully.`);
        res.status(200).json({ message: "Ballot accepted and queued for processing!" });

    } catch (err) {
        console.error("Critical Error:", err);
        res.status(500).json({ error: "Internal security error. Please try again." });
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Election API Online on port ${PORT}`));