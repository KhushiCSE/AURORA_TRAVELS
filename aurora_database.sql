-- ======================================================
-- 1. TABLES (DDL - Data Definition Language)
-- ======================================================

-- 1.1 Passenger Info (3NF: Master Data)
-- 1. Temporarily disable foreign key constraints
SET FOREIGN_KEY_CHECKS = 0;

-- 2. Drop only the problematic table
DROP TABLE IF EXISTS passengers;

-- 3. Re-create the table with the correct NOT NULL and INDEX settings
CREATE TABLE passengers (
    passport_number VARCHAR(50) PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    dob DATE,
    gender ENUM('Male', 'Female', 'Other'),
    nationality VARCHAR(100),
    phone VARCHAR(20),
    email VARCHAR(100) NOT NULL, -- This ensures login always has an email to check
    INDEX idx_passenger_email (email) -- This makes your login query super fast
);

-- 4. Re-enable safety checks
SET FOREIGN_KEY_CHECKS = 1;


-- 1.2 Bookings (Central Transaction Table)
CREATE TABLE bookings (
    booking_id INT AUTO_INCREMENT PRIMARY KEY,
    passport_number VARCHAR(50),
    dep_city VARCHAR(100),
    dest_city VARCHAR(100),
    dep_date DATE,
    num_passengers INT,
    base_price DECIMAL(10,2),
    total_amount DECIMAL(10,2), -- Calculated as (base*passengers) + 5% GST
    status ENUM('Pending', 'Confirmed', 'Failed') DEFAULT 'Pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (passport_number) REFERENCES passengers(passport_number) ON DELETE CASCADE
);

SELECT * FROM bookings;

-- 1.3 Master Payment Table
CREATE TABLE payments (
    payment_id INT AUTO_INCREMENT PRIMARY KEY,
    booking_id INT,
    method ENUM('Card', 'UPI', 'NetBanking', 'AmazonPay'),
    amount_paid DECIMAL(10,2),
    status ENUM('Success', 'Failed'),
    transaction_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (booking_id) REFERENCES bookings(booking_id)
);

-- 1.4 Normalized Payment Details (3NF: Specific to Method)
CREATE TABLE payment_card_details (
    payment_id INT PRIMARY KEY,
    card_number_masked VARCHAR(20), -- For security, usually masked
    cvv_hidden VARCHAR(4), 
    FOREIGN KEY (payment_id) REFERENCES payments(payment_id)
);

CREATE TABLE payment_upi_details (
    payment_id INT PRIMARY KEY,
    upi_id VARCHAR(100),
    FOREIGN KEY (payment_id) REFERENCES payments(payment_id)
);

-- 1.5 Final Issued Tickets (For Ticket Page)
CREATE TABLE issued_tickets (
    ticket_id INT AUTO_INCREMENT PRIMARY KEY,
    booking_id INT UNIQUE,
    pnr_number VARCHAR(20) UNIQUE,
    issue_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (booking_id) REFERENCES bookings(booking_id)
);

-- 1.6 Audit Table: Failed Transactions
CREATE TABLE failed_logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    booking_id INT,
    reason VARCHAR(255),
    fail_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ======================================================
-- 2. VIEWS (DQL - Data Query Language)
-- ======================================================

-- View for "Fare Summary" logic
CREATE VIEW view_fare_summaries AS
SELECT 
    booking_id, 
    num_passengers, 
    base_price, 
    (base_price * num_passengers) AS subtotal,
    total_amount AS grand_total 
FROM bookings;

-- View for "Confirmed Tickets" (Used for ticket.html)
CREATE VIEW active_tickets AS
SELECT 
    b.booking_id,
    p.full_name,
    p.passport_number,
    b.dep_city,
    b.dest_city,
    b.dep_date,
    b.status,
    b.total_amount
FROM bookings b
JOIN passengers p ON b.passport_number = p.passport_number
WHERE b.status = 'Confirmed';

-- ======================================================
-- 3. PROCEDURES (Logic & Transactions)
-- ======================================================

DELIMITER //

-- Procedure to finalize a successful payment
CREATE PROCEDURE ProcessSuccessfulPayment(IN b_id INT, IN p_method VARCHAR(50))
BEGIN
    START TRANSACTION; -- TCL: Transaction Control
    
    -- Update Booking Status
    UPDATE bookings SET status = 'Confirmed' WHERE booking_id = b_id;
    
    -- Insert into Payments
    INSERT INTO payments (booking_id, method, amount_paid, status) 
    SELECT booking_id, p_method, total_amount, 'Success' FROM bookings WHERE booking_id = b_id;
    
    -- Generate Ticket
    INSERT INTO issued_tickets (booking_id, pnr_number) 
    VALUES (b_id, CONCAT('AUR', LPAD(b_id, 5, '0')));
    
    COMMIT;
END //

DELIMITER ;

-- ======================================================
-- 4. TRIGGERS (Automated Audit)
-- ======================================================

DELIMITER //

-- Auto-log when a booking is marked as 'Failed'
CREATE TRIGGER after_booking_fail
AFTER UPDATE ON bookings
FOR EACH ROW
BEGIN
    IF NEW.status = 'Failed' THEN
        INSERT INTO failed_logs (booking_id, reason)
        VALUES (NEW.booking_id, 'Payment declined by user/bank');
    END IF;
END //

DELIMITER ;
CREATE TABLE cancelled_tickets AS 
SELECT * FROM bookings WHERE 1=0;

-- Add a column to track when it was cancelled
ALTER TABLE cancelled_tickets ADD COLUMN cancelled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;



-- 3. Ensure the passengers table has the email column for login
-- (Your existing code might already have this, but this ensures it is there)
ALTER TABLE passengers 
MODIFY COLUMN email VARCHAR(100) NOT NULL;

-- 4. Create an index on email to make the login process faster
-- Use this instead of the single CREATE INDEX line
-- It checks if the index is already there before trying to add it
-- Run this to safely handle the index without errors

-- Disable checks so we can empty linked tables
-- to delete the records whenever required 
SET FOREIGN_KEY_CHECKS = 0;

-- Empty the tables
TRUNCATE TABLE cancelled_tickets;
TRUNCATE TABLE bookings;
TRUNCATE TABLE passengers;

-- Re-enable checks
SET FOREIGN_KEY_CHECKS = 1;
-- For the normal views
SELECT * FROM active_tickets;
SELECT * FROM cancelled_tickets;
-- synchornization of the passport number and email
-- 1. Ensure the email column exists and is mandatory
ALTER TABLE passengers MODIFY COLUMN email VARCHAR(100) NOT NULL;

-- 2. Add an index to make the login verification fast
CREATE INDEX idx_login_lookup ON passengers(email, passport_number);
