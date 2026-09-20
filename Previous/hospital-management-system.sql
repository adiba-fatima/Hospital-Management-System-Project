CREATE DATABASE hospital_management_system;
USE hospital_management_system;

CREATE TABLE patients
(
    patientid INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    age INT,
    gender ENUM('male', 'female', 'other'),
    phonenumber VARCHAR(20),
    bloodgroup ENUM('A+','A-','B+','B-','AB+','AB-','O+','O-'),
    lastupdated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE doctors
(
    doctorid INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    specialization VARCHAR(50),
    email VARCHAR(50) unique
);

CREATE TABLE appointments
(
    appointmentid INT AUTO_INCREMENT PRIMARY KEY,
    patientid INT,
    doctorid INT,
    appointmentdate DATE,
    status ENUM('Scheduled', 'Completed', 'Cancelled') DEFAULT 'Scheduled',
    FOREIGN KEY (patientid) REFERENCES patients(patientid),
    FOREIGN KEY (doctorid) REFERENCES doctors(doctorid),
    UNIQUE KEY uq_patient_doctor_date (patientid, doctorid, appointmentdate)
);

CREATE TABLE appointmentlog
(
    logid INT AUTO_INCREMENT PRIMARY KEY,
    appointmentid INT,
    action varchar(50),
    actiontime TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (appointmentid) REFERENCES appointments(appointmentid)
);

CREATE TABLE appointmentstatus
(
    doctorid INT PRIMARY KEY,
    total_appointments INT DEFAULT 0,
    FOREIGN KEY (doctorid) REFERENCES doctors(doctorid)
);

INSERT INTO patients (name, age, gender, phonenumber, bloodgroup)
VALUES ('adiba', 21, 'female', '01743489277','O+'),
('fatima', 21, 'female','01982384721','B+'),
('tushar', 25, 'male','01982384721','A+'),
('afsari', 23, 'female','01982384721','A+'),
('nishi', 23, 'female', '01982384721','B+'),
('naima', 22, 'female', '01982384721','A+'),
('amena', 23, 'female','01982384721','O+'),
('ishraq', 27, 'male', '01982384721','O+'),
('sajjad', 57, 'male','01982384721','A+'),
('maria', 45, 'female', '01982384721','AB+'),
('nirob', 25, 'male', '01982384721','A+'),
('faiza', 37, 'female', '01982384721','A-'),
('abrar', 29, 'male', '01982384721','B-');

INSERT INTO doctors (name, specialization, email)
VALUES ('Dr. Karim', 'Cardiology', 'karim@hospital.com'),
('Dr. Rezaul', 'Oncology','rezaul@hospital.com'),
('Dr. Rashed', 'Gynacology','rashed@hospital.com'),
('Dr. Foysal',  'Medicine Specialist', 'foysal@hospital.com'),
('Dr. Jahid', 'Neurology', 'jahid@hospital.com'),
('Dr. Sultana', 'Dermatology', 'sultana@hospital.com');

INSERT INTO appointments (patientid, doctorid, appointmentdate, status)
VALUES (1, 1, '2026-09-20', 'Scheduled'),
(2, 1, '2026-09-20', 'Scheduled'),
(3, 2, '2026-09-20', 'Scheduled'),
(4, 3, '2026-09-20', 'Scheduled'),
(5, 2, '2026-09-20', 'Scheduled'),
(6, 4, '2026-09-20', 'Scheduled'),
(7, 5, '2026-09-20', 'Scheduled'),
(8, 6, '2026-09-20', 'Scheduled'),
(9, 4, '2026-09-20', 'Scheduled'),
(10, 6, '2026-09-20', 'Scheduled'),
(11, 4, '2026-09-20', 'Scheduled'),
(12, 5, '2026-09-20', 'Scheduled');

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
INSERT INTO appointmentlog (appointmentid, action)
VALUES (NEW.appointmentid, CONCAT('Created with status ', NEW.status));
IF NEW.status = 'Scheduled' THEN
INSERT INTO appointmentstatus (doctorid, total_appointments)
VALUES (NEW.doctorid, 1)
ON DUPLICATE KEY UPDATE total_appointments = total_appointments + 1;
END IF;
END &&
DELIMITER ;

DELIMITER &&
CREATE TRIGGER afterappointment_update
AFTER UPDATE ON appointments
FOR EACH ROW
BEGIN
IF NEW.status <> OLD.status THEN
INSERT INTO appointmentlog (appointmentid, action)
VALUES (NEW.appointmentid, CONCAT('Status changed from ', OLD.status, ' to ', NEW.status));
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
DELIMITER ;

DELIMITER &&
CREATE TRIGGER afterappointment_delete
AFTER DELETE ON appointments
FOR EACH ROW
BEGIN
IF OLD.status = 'Scheduled' THEN
UPDATE appointmentstatus
SET total_appointments = total_appointments - 1
WHERE doctorid = OLD.doctorid;
END IF;
END &&
DELIMITER ;

CREATE VIEW appointment_details AS
SELECT a.appointmentid, p.name AS patient, d.name AS doctor, a.appointmentdate, a.status
FROM appointments a
JOIN patients p ON a.patientid = p.patientid
JOIN doctors d ON a.doctorid = d.doctorid;


CREATE VIEW doctor_scheduled_counts AS
SELECT d.doctorid, d.name, COUNT(a.appointmentid) AS total_scheduled
FROM doctors d
LEFT JOIN appointments a
    ON a.doctorid = d.doctorid AND a.status = 'Scheduled'
GROUP BY d.doctorid, d.name;


select * from patients;
select * from doctors;
select * from appointments;
SELECT * FROM appointmentstatus ORDER BY doctorid;
select * from appointmentlog;

select * from appointment_details;
SELECT * FROM doctor_scheduled_counts ORDER BY doctorid;   

INSERT INTO appointments (patientid, doctorid, appointmentdate, status)
VALUES (1, 1, '2026-10-01', 'Scheduled');
SELECT * FROM appointmentstatus WHERE doctorid = 1;        

UPDATE appointments SET status = 'Completed' WHERE appointmentid = 1;
SELECT * FROM appointmentlog WHERE appointmentid = 1;       
SELECT * FROM appointmentstatus WHERE doctorid = 1;         

drop database hospital_management_system