CREATE DATABASE IF NOT EXISTS hospital_management_system;
USE hospital_management_system;

DROP VIEW IF EXISTS doctor_scheduled_counts;
DROP VIEW IF EXISTS appointment_details;
DROP TRIGGER IF EXISTS afterappointment_insert;
DROP TRIGGER IF EXISTS afterappointment_update;
DROP TRIGGER IF EXISTS afterappointment_delete;
DROP TABLE IF EXISTS appointmentstatus;
DROP TABLE IF EXISTS appointmentlog;
DROP TABLE IF EXISTS appointments;
DROP TABLE IF EXISTS doctors;
DROP TABLE IF EXISTS patients;

CREATE TABLE patients (
    patientid INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    age INT,
    gender ENUM('male', 'female', 'other'),
    phonenumber VARCHAR(20),
    bloodgroup ENUM('A+','A-','B+','B-','AB+','AB-','O+','O-'),
    lastupdated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE doctors (
    doctorid INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    specialization VARCHAR(50),
    email VARCHAR(50) UNIQUE
) ENGINE=InnoDB;

CREATE TABLE appointments (
    appointmentid INT AUTO_INCREMENT PRIMARY KEY,
    patientid INT,
    doctorid INT,
    appointmentdate DATE,
    appointmenttime TIME NOT NULL DEFAULT '09:00:00',
    status ENUM('Scheduled', 'Completed', 'Cancelled') DEFAULT 'Scheduled',
    FOREIGN KEY (patientid) REFERENCES patients(patientid),
    FOREIGN KEY (doctorid) REFERENCES doctors(doctorid),
    UNIQUE KEY uq_patient_doctor_date (patientid, doctorid, appointmentdate),
    UNIQUE KEY uq_doctor_date_time (doctorid, appointmentdate, appointmenttime)
) ENGINE=InnoDB;

CREATE TABLE appointmentlog (
    logid INT AUTO_INCREMENT PRIMARY KEY,
    appointmentid INT,
    action VARCHAR(100),
    patientname VARCHAR(100),
    doctorname VARCHAR(100),
    appointmentdate DATE,
    appointmenttime TIME,
    actiontime TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (appointmentid) REFERENCES appointments(appointmentid) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE appointmentstatus (
    doctorid INT PRIMARY KEY,
    total_appointments INT DEFAULT 0,
    FOREIGN KEY (doctorid) REFERENCES doctors(doctorid)
) ENGINE=InnoDB;

INSERT INTO patients (name, age, gender, phonenumber, bloodgroup) VALUES
('adiba', 21, 'female', '01743489277', 'O+'),
('fatima', 21, 'female', '01982384721', 'B+'),
('tushar', 25, 'male', '01982384721', 'A+'),
('afsari', 23, 'female', '01982384721', 'A+'),
('nishi', 23, 'female', '01982384721', 'B+'),
('naima', 22, 'female', '01982384721', 'A+'),
('amena', 23, 'female', '01982384721', 'O+'),
('ishraq', 27, 'male', '01982384721', 'O+'),
('sajjad', 57, 'male', '01982384721', 'A+'),
('maria', 45, 'female', '01982384721', 'AB+'),
('nirob', 25, 'male', '01982384721', 'A+'),
('faiza', 37, 'female', '01982384721', 'A-'),
('abrar', 29, 'male', '01982384721', 'B-');

INSERT INTO doctors (name, specialization, email) VALUES
('Dr. Karim', 'Cardiology', 'karim@hospital.com'),
('Dr. Rezaul', 'Oncology', 'rezaul@hospital.com'),
('Dr. Rashed', 'Gynacology', 'rashed@hospital.com'),
('Dr. Foysal', 'Medicine Specialist', 'foysal@hospital.com'),
('Dr. Jahid', 'Neurology', 'jahid@hospital.com'),
('Dr. Sultana', 'Dermatology', 'sultana@hospital.com');

INSERT INTO appointments (patientid, doctorid, appointmentdate, appointmenttime, status) VALUES
(1, 1, '2026-09-20', '09:00:00', 'Scheduled'),
(2, 1, '2026-09-20', '09:30:00', 'Scheduled'),
(3, 2, '2026-09-20', '10:00:00', 'Scheduled'),
(4, 3, '2026-09-20', '10:30:00', 'Scheduled'),
(5, 2, '2026-09-20', '11:00:00', 'Scheduled'),
(6, 4, '2026-09-20', '14:00:00', 'Scheduled'),
(7, 5, '2026-09-20', '11:30:00', 'Scheduled'),
(8, 6, '2026-09-20', '12:00:00', 'Scheduled'),
(9, 4, '2026-09-20', '15:30:00', 'Scheduled'),
(10, 6, '2026-09-20', '13:00:00', 'Scheduled'),
(11, 4, '2026-09-20', '16:00:00', 'Scheduled'),
(12, 5, '2026-09-20', '12:00:00', 'Scheduled');

INSERT INTO appointmentstatus (doctorid, total_appointments)
SELECT doctorid, COUNT(*)
FROM appointments
WHERE status = 'Scheduled'
GROUP BY doctorid;

DELIMITER &&

CREATE TRIGGER afterappointment_insert
AFTER INSERT ON appointments
FOR EACH ROW
BEGIN
    INSERT INTO appointmentlog
        (appointmentid, action, patientname, doctorname, appointmentdate, appointmenttime)
    SELECT NEW.appointmentid, CONCAT('Created with status ', NEW.status),
           p.name, d.name, NEW.appointmentdate, NEW.appointmenttime
    FROM patients p
    JOIN doctors d ON d.doctorid = NEW.doctorid
    WHERE p.patientid = NEW.patientid;
    IF NEW.status = 'Scheduled' THEN
        INSERT INTO appointmentstatus (doctorid, total_appointments)
        VALUES (NEW.doctorid, 1)
        ON DUPLICATE KEY UPDATE total_appointments = total_appointments + 1;
    END IF;
END &&

CREATE TRIGGER afterappointment_update
AFTER UPDATE ON appointments
FOR EACH ROW
BEGIN
    IF NOT (NEW.patientid <=> OLD.patientid)
       OR NOT (NEW.doctorid <=> OLD.doctorid)
       OR NOT (NEW.appointmentdate <=> OLD.appointmentdate)
       OR NOT (NEW.appointmenttime <=> OLD.appointmenttime)
       OR NOT (NEW.status <=> OLD.status) THEN
        INSERT INTO appointmentlog
            (appointmentid, action, patientname, doctorname, appointmentdate, appointmenttime)
        SELECT NEW.appointmentid,
               CASE
                   WHEN NEW.status <> OLD.status
                       THEN CONCAT('Status changed from ', OLD.status, ' to ', NEW.status)
                   ELSE 'Appointment rescheduled'
               END,
               p.name, d.name, NEW.appointmentdate, NEW.appointmenttime
        FROM patients p
        JOIN doctors d ON d.doctorid = NEW.doctorid
        WHERE p.patientid = NEW.patientid;
        IF NEW.status IN ('Completed', 'Cancelled') AND OLD.status = 'Scheduled' THEN
            UPDATE appointmentstatus
            SET total_appointments = total_appointments - 1
            WHERE doctorid = OLD.doctorid;
        END IF;
        IF NEW.status = 'Scheduled' AND OLD.status IN ('Completed', 'Cancelled') THEN
            UPDATE appointmentstatus
            SET total_appointments = total_appointments + 1
            WHERE doctorid = NEW.doctorid;
        END IF;
    END IF;
END &&
CREATE TRIGGER afterappointment_delete
BEFORE DELETE ON appointments
FOR EACH ROW
BEGIN
    INSERT INTO appointmentlog
        (appointmentid, action, patientname, doctorname, appointmentdate, appointmenttime)
    SELECT OLD.appointmentid, 'Appointment deleted',
           p.name, d.name, OLD.appointmentdate, OLD.appointmenttime
    FROM patients p
    JOIN doctors d ON d.doctorid = OLD.doctorid
    WHERE p.patientid = OLD.patientid;
    IF OLD.status = 'Scheduled' THEN
        UPDATE appointmentstatus
        SET total_appointments = total_appointments - 1
        WHERE doctorid = OLD.doctorid;
    END IF;
END &&

DELIMITER ;

CREATE VIEW appointment_details AS
SELECT a.appointmentid, p.name AS patient, d.name AS doctor,
       a.appointmentdate, a.appointmenttime, a.status
FROM appointments a
JOIN patients p ON a.patientid = p.patientid
JOIN doctors d ON a.doctorid = d.doctorid;

CREATE VIEW doctor_scheduled_counts AS
SELECT d.doctorid, d.name, COUNT(a.appointmentid) AS total_scheduled
FROM doctors d
LEFT JOIN appointments a
    ON a.doctorid = d.doctorid AND a.status = 'Scheduled'
GROUP BY d.doctorid, d.name;
