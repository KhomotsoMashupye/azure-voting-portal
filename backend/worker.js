const { ServiceBusClient } = require("@azure/service-bus");
const { Pool } = require('pg');


const pool = new Pool({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: 'online-voting_db',
    port: 5432,
    ssl: { rejectUnauthorized: false } 
});


const connectionString = process.env.SERVICE_BUS_CONNECTION_STRING;
const queueName = "vote-queue";

async function startWorker() {
    const sbClient = new ServiceBusClient(connectionString);
    const receiver = sbClient.createReceiver(queueName);

    console.log("Worker Service: Monitoring 'vote-queue' for new ballots...");

    const processMessage = async (messageReceived) => {
        const { candidate, voterId, timestamp } = messageReceived.body;
        
        console.log(`Processing message: Vote for ${candidate} by Voter ${voterId}`);

        try {
            
            const queryText = 'INSERT INTO votes (voter_id, candidate, cast_at) VALUES ($1, $2, $3)';
            await pool.query(queryText, [voterId, candidate, timestamp]);
            
            console.log(`[SUCCESS] Vote finalized in Database.`);
            
            
            await receiver.completeMessage(messageReceived);
        } catch (err) {
            console.error("[ERROR] Failed to write to DB:", err.message);
            
        }
    };

    const processError = async (args) => {
        console.error(`Service Bus Error: ${args.error}`);
    };

    receiver.subscribe({
        processMessage,
        processError
    });
}

startWorker().catch((err) => {
    console.error("Worker failed to start:", err);
    process.exit(1);
});