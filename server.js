const express = require('express');
const mysql = require('mysql2');
const cors = require('cors');
const bodyParser = require('body-parser');

const app = express();
app.use(cors());
app.use(bodyParser.json());

// 1. DATABASE CONNECTION
const db = mysql.createConnection({
    host: 'localhost',
    user: 'root',
    password: 'root', // <--- DOUBLE CHECK THIS: Use the password that worked in your CMD
    database: 'aurora_travels'
});

db.connect(err => {
    if (err) {
        console.error('Database connection failed: ' + err.stack);
        return;
    }
    console.log('CONNECTED: MySQL Database "aurora_travels" is ready.');
});

// 2. CREATE OPERATION (Booking & Passenger)
// Triggered when user clicks "Confirm" on booking.html

app.post('/api/book', (req, res) => {
    const { fullName, passport, email, depCity, destCity, depDate, numPassengers, basePrice } = req.body;
    
    // Calculate total including 5% GST (Matches your frontend logic)
    const total = (basePrice * numPassengers) * 1.05;

    // First: Insert/Update Passenger (Referential Integrity)
    const passengerSql = "INSERT INTO passengers (passport_number, full_name, email) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE full_name = VALUES(full_name), email = VALUES(email)";
    
   db.query(passengerSql, [passport, fullName, email], (err) => {
        if (err) return res.status(500).send(err);

        // Second: Create Booking in 'Pending' status
        const bookingSql = "INSERT INTO bookings (passport_number, dep_city, dest_city, dep_date, num_passengers, base_price, total_amount, status) VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending')";
        
        db.query(bookingSql, [passport, depCity, destCity, depDate, numPassengers, basePrice, total], (err, result) => {
            if (err) return res.status(500).send(err);
            
            console.log(`Booking Created! ID: ${result.insertId}`);
            res.send({ bookingId: result.insertId });
        });
    });
});

// 3. UPDATE OPERATION (Confirm Payment via STORED PROCEDURE)
// Triggered when user finishes payment on Final_payment.html
app.post('/api/payment-success', (req, res) => {
    const { bookingId, method } = req.body;
    
    // We call the stored procedure you created in MySQL to handle Status Update + Ticket Generation
    const sql = "CALL ProcessSuccessfulPayment(?, ?)";
    
    db.query(sql, [bookingId, method], (err) => {
        if (err) {
            console.error("Payment Error:", err);
            return res.status(500).send(err);
        }
        console.log(`Payment Success for Booking ID: ${bookingId}`);
        res.send({ message: "Transaction Completed Successfully" });
    });
});

// 4. RETRIEVE OPERATION (For Ticket Page)
app.get('/api/ticket/:id', (req, res) => {
    const sql = "SELECT * FROM active_tickets WHERE booking_id = ?";
    db.query(sql, [req.params.id], (err, result) => {
        if (err) return res.status(500).send(err);
        res.send(result[0]);
    });
});
app.delete('/api/cancel', (req, res) => {
    const { passport } = req.body;

    // 1. Disable Foreign Key checks temporarily to allow the move
    db.query("SET FOREIGN_KEY_CHECKS = 0", (err) => {
        
        // 2. Move data to cancelled_tickets
        const moveQuery = `
            INSERT INTO cancelled_tickets (booking_id, passport_number, dep_city, dest_city, dep_date, status, total_amount)
            SELECT booking_id, passport_number, dep_city, dest_city, dep_date, status, total_amount 
            FROM bookings WHERE passport_number = ?`;

        db.query(moveQuery, [passport], (err, result) => {
            if (err) {
                db.query("SET FOREIGN_KEY_CHECKS = 1"); // Re-enable on error
                return res.status(500).json({ message: "Error archiving ticket" });
            }
            
            if (result.affectedRows === 0) {
                db.query("SET FOREIGN_KEY_CHECKS = 1");
                return res.status(404).json({ message: "No booking found with this passport." });
            }

            // 3. Delete from original table
            const deleteQuery = `DELETE FROM bookings WHERE passport_number = ?`;

            db.query(deleteQuery, [passport], (err2) => {
                // 4. IMPORTANT: Always re-enable Foreign Key checks!
                db.query("SET FOREIGN_KEY_CHECKS = 1");

                if (err2) return res.status(500).json({ message: "Error deleting original record" });
                res.json({ message: "Ticket successfully cancelled and archived!" });
            });
        });
    });
});

// 5. LOGIN OPERATION (For Dashboard)
app.post('/api/login', (req, res) => {
    const { email, passport } = req.body;

    const sql = "SELECT * FROM passengers WHERE email = ? AND passport_number = ?";

    db.query(sql, [email, passport], (err, result) => {
        if (err) return res.status(500).send({ message: "Server error" });

        if (result.length === 0) {
            return res.status(401).send({ message: "Invalid email or passport number!" });
        }

        // Login success — send passenger info back
        res.send({ 
            success: true, 
            user: {
                full_name: result[0].full_name,
                passport_number: result[0].passport_number
            }
        });
    });
});

// 6. GET USER BOOKINGS (For Dashboard)
app.get('/api/user-bookings/:passport', (req, res) => {
    const sql = "SELECT * FROM active_tickets WHERE passport_number = ?";
    db.query(sql, [req.params.passport], (err, result) => {
        if (err) return res.status(500).send({ message: "Server error" });
        res.send(result);
    });
});

app.listen(3000, () => {
    console.log('-------------------------------------------');
    console.log('AURORA TRAVELS SERVER RUNNING ON PORT 3000');
    console.log('-------------------------------------------');
});