const express = require('express');
const mysql = require('mysql2/promise');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3005;

const dbConfig = {
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || 'root',
  database: process.env.DB_NAME || 'hospital_management_system',
  port: Number(process.env.DB_PORT || 3306),
};

const pool = mysql.createPool(dbConfig);

app.use(express.json());
app.use(express.static(__dirname));

async function getAllAppointments() {
  const [rows] = await pool.query(`
    SELECT
      a.appointmentid AS id,
      DATE_FORMAT(a.appointmentdate, '%Y-%m-%d') AS date,
      TIME_FORMAT(a.appointmenttime, '%H:%i:%s') AS time,
      a.status,
      p.patientid AS patientId,
      p.name AS patient,
      d.name AS doctor,
      d.specialization AS department
    FROM appointments a
    JOIN patients p ON p.patientid = a.patientid
    JOIN doctors d ON d.doctorid = a.doctorid
    ORDER BY a.appointmentdate, a.appointmentid
  `);

  return rows.map((row) => ({
    ...row,
    patient: row.patient.trim(),
    doctor: row.doctor.trim(),
  }));
}

async function getActivityLog() {
  const [rows] = await pool.query(`
    SELECT
      CASE
        WHEN al.action LIKE 'Created with status%' THEN 'Scheduled'
        WHEN al.action LIKE 'Status changed from%to Completed' THEN 'Completed'
        WHEN al.action = 'Appointment rescheduled' THEN 'Rescheduled'
        WHEN al.action = 'Appointment deleted' THEN 'Deleted'
        ELSE al.action
      END AS action,
      COALESCE(p.name, al.patientname) AS patientName,
      COALESCE(d.name, al.doctorname) AS doctorName,
      al.appointmentid AS appointmentId,
      DATE_FORMAT(COALESCE(a.appointmentdate, al.appointmentdate), '%Y-%m-%d') AS appointmentDate,
      TIME_FORMAT(COALESCE(a.appointmenttime, al.appointmenttime), '%H:%i:%s') AS appointmentTime,
      DATE_FORMAT(al.actiontime, '%b %d, %Y %l:%i %p') AS loggedAt
    FROM appointmentlog al
    LEFT JOIN appointments a ON a.appointmentid = al.appointmentid
    LEFT JOIN patients p ON p.patientid = a.patientid
    LEFT JOIN doctors d ON d.doctorid = a.doctorid
    ORDER BY al.actiontime DESC
    LIMIT 20
  `);

  return rows;
}

async function ensureActivityEntry(appointmentId, actionPattern, fallbackAction) {
  const [appointmentRows] = await pool.query(
    `SELECT a.appointmentid, p.name AS patientname, d.name AS doctorname,
            a.appointmentdate, a.appointmenttime
     FROM appointments a
     JOIN patients p ON p.patientid = a.patientid
     JOIN doctors d ON d.doctorid = a.doctorid
     WHERE a.appointmentid = ?`,
    [appointmentId]
  );

  if (!appointmentRows.length) return;
  const appointment = appointmentRows[0];
  const [logs] = await pool.query(
    'SELECT logid FROM appointmentlog WHERE appointmentid = ? AND action LIKE ? ORDER BY logid DESC LIMIT 1',
    [appointmentId, actionPattern]
  );

  let logId = logs[0]?.logid;
  if (!logId) {
    const [result] = await pool.query(
      `INSERT INTO appointmentlog
       (appointmentid, action, patientname, doctorname, appointmentdate, appointmenttime)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        appointmentId,
        fallbackAction,
        appointment.patientname,
        appointment.doctorname,
        appointment.appointmentdate,
        appointment.appointmenttime,
      ]
    );
    logId = result.insertId;
  } else {
    await pool.query(
      `UPDATE appointmentlog
       SET patientname = ?, doctorname = ?, appointmentdate = ?, appointmenttime = ?
       WHERE logid = ?`,
      [
        appointment.patientname,
        appointment.doctorname,
        appointment.appointmentdate,
        appointment.appointmenttime,
        logId,
      ]
    );
  }
}

app.get('/api/appointments', async (req, res) => {
  try {
    const appointments = await getAllAppointments();
    res.json(appointments);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/activity', async (req, res) => {
  try {
    const logs = await getActivityLog();
    res.json(logs);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/appointments', async (req, res) => {
  try {
    const { patient, doctor, department, date, time } = req.body;

    if (!patient || !doctor || !department || !date || !time) {
      return res.status(400).json({ error: 'Patient, doctor, department, date and time are required.' });
    }

    const cleanDoctor = doctor.trim();
    const cleanPatient = patient.trim();
    const [doctorRows] = await pool.query(
      'SELECT doctorid FROM doctors WHERE name = ? AND specialization = ?',
      [cleanDoctor, department]
    );

    if (!doctorRows.length) {
      return res.status(400).json({ error: 'Selected doctor is not available in this department.' });
    }

    const doctorId = doctorRows[0].doctorid;

    const [slotCheck] = await pool.query(
      'SELECT appointmentid FROM appointments WHERE doctorid = ? AND appointmentdate = ? AND appointmenttime = ?',
      [doctorId, date, time]
    );

    if (slotCheck.length) {
      return res.status(409).json({ error: 'That doctor is already booked at this date and time. Please choose another slot.' });
    }

    const [patientResult] = await pool.query(
      'INSERT INTO patients (name, age, gender, phonenumber, bloodgroup) VALUES (?, 30, "other", "", "O+")',
      [cleanPatient]
    );

    const patientId = patientResult.insertId;

    const [appointmentResult] = await pool.query(
      'INSERT INTO appointments (patientid, doctorid, appointmentdate, appointmenttime, status) VALUES (?, ?, ?, ?, "Scheduled")',
      [patientId, doctorId, date, time]
    );
    await ensureActivityEntry(appointmentResult.insertId, 'Created with status%', 'Created with status Scheduled');

    res.status(201).json({ message: 'Appointment created successfully.' });
  } catch (error) {
    if (error.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ error: 'That doctor is already booked at this date and time. Please choose another slot.' });
    }
    res.status(500).json({ error: error.message });
  }
});

app.patch('/api/appointments/:id/complete', async (req, res) => {
  try {
    const { id } = req.params;
    const [result] = await pool.query(
      'UPDATE appointments SET status = "Completed" WHERE appointmentid = ?',
      [id]
    );

    if (!result.affectedRows) {
      return res.status(404).json({ error: 'Appointment not found.' });
    }

    await ensureActivityEntry(id, '%to Completed', 'Status changed to Completed');

    res.json({ message: 'Appointment marked as completed.' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.delete('/api/appointments/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const [appointment] = await pool.query(
      `SELECT a.appointmentid, p.name AS patientname, d.name AS doctorname,
              a.appointmentdate, a.appointmenttime
       FROM appointments a
       JOIN patients p ON p.patientid = a.patientid
       JOIN doctors d ON d.doctorid = a.doctorid
       WHERE a.appointmentid = ?`,
      [id]
    );

    if (!appointment.length) {
      return res.status(404).json({ error: 'Appointment not found.' });
    }

    const deleteStartedAt = new Date();
    await pool.query(
      'UPDATE appointmentlog SET appointmentid = NULL WHERE appointmentid = ?',
      [id]
    );
    await pool.query('DELETE FROM appointments WHERE appointmentid = ?', [id]);

    const deletedAppointment = appointment[0];
    const [deleteLogs] = await pool.query(
      `SELECT logid, patientname
       FROM appointmentlog
       WHERE action = 'Appointment deleted' AND actiontime >= ?
       ORDER BY logid DESC
      LIMIT 1`,
          [deleteStartedAt]
    );

    if (deleteLogs.length && !deleteLogs[0].patientname) {
      await pool.query(
        `UPDATE appointmentlog
         SET patientname = ?, doctorname = ?, appointmentdate = ?, appointmenttime = ?
         WHERE logid = ?`,
        [
          deletedAppointment.patientname,
          deletedAppointment.doctorname,
          deletedAppointment.appointmentdate,
          deletedAppointment.appointmenttime,
          deleteLogs[0].logid,
        ]
      );
    } else if (!deleteLogs.length) {
      await pool.query(
        `INSERT INTO appointmentlog
         (appointmentid, action, patientname, doctorname, appointmentdate, appointmenttime)
         VALUES (NULL, 'Appointment deleted', ?, ?, ?, ?)`,
        [
          deletedAppointment.patientname,
          deletedAppointment.doctorname,
          deletedAppointment.appointmentdate,
          deletedAppointment.appointmenttime,
        ]
      );
    }

    res.json({ message: 'Appointment deleted.' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.put('/api/appointments/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { patient, doctor, department, date, time } = req.body;

    if (!patient || !doctor || !department || !date || !time) {
      return res.status(400).json({ error: 'All fields are required.' });
    }

    const [doctorRows] = await pool.query(
      'SELECT doctorid FROM doctors WHERE name = ? AND specialization = ?',
      [doctor, department]
    );

    if (!doctorRows.length) {
      return res.status(400).json({ error: 'Selected doctor is not available in this department.' });
    }

    const [appointmentExists] = await pool.query(
      'SELECT appointmentid FROM appointments WHERE doctorid = ? AND appointmentdate = ? AND appointmenttime = ? AND appointmentid != ?',
      [doctorRows[0].doctorid, date, time, id]
    );

    if (appointmentExists.length) {
      return res.status(409).json({ error: 'That doctor is already booked at this date and time. Please choose another slot.' });
    }

    const [patientResult] = await pool.query(
      'SELECT patientid FROM patients WHERE name = ? LIMIT 1',
      [patient.trim()]
    );

    const patientId = patientResult[0]?.patientid || null;

    if (patientId) {
      await pool.query(
        'UPDATE appointments SET patientid = ?, doctorid = ?, appointmentdate = ?, appointmenttime = ? WHERE appointmentid = ?',
        [patientId, doctorRows[0].doctorid, date, time, id]
      );
    } else {
      const [newPatient] = await pool.query(
        'INSERT INTO patients (name, age, gender, phonenumber, bloodgroup) VALUES (?, 30, "other", "", "O+")',
        [patient.trim()]
      );
      await pool.query(
        'UPDATE appointments SET patientid = ?, doctorid = ?, appointmentdate = ?, appointmenttime = ? WHERE appointmentid = ?',
        [newPatient.insertId, doctorRows[0].doctorid, date, time, id]
      );
    }

    await ensureActivityEntry(id, 'Appointment rescheduled', 'Appointment rescheduled');
    res.json({ message: 'Appointment updated successfully.' });
  } catch (error) {
    if (error.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ error: 'That doctor is already booked at this date and time. Please choose another slot.' });
    }
    res.status(500).json({ error: error.message });
  }
});

app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

async function ensureActivityLogColumns() {
  const [columns] = await pool.query(
    `SELECT COLUMN_NAME
     FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'appointmentlog'`,
    [dbConfig.database]
  );
  const existingColumns = new Set(columns.map((column) => column.COLUMN_NAME));
  const requiredColumns = [
    ['patientname', 'VARCHAR(100)'],
    ['doctorname', 'VARCHAR(100)'],
    ['appointmentdate', 'DATE'],
    ['appointmenttime', 'TIME'],
  ];

  for (const [columnName, columnType] of requiredColumns) {
    if (!existingColumns.has(columnName)) {
      await pool.query(`ALTER TABLE appointmentlog ADD COLUMN ${columnName} ${columnType}`);
    }
  }

  await pool.query(`
    UPDATE appointmentlog al
    JOIN appointments a ON a.appointmentid = al.appointmentid
    JOIN patients p ON p.patientid = a.patientid
    JOIN doctors d ON d.doctorid = a.doctorid
    SET al.patientname = COALESCE(al.patientname, p.name),
        al.doctorname = COALESCE(al.doctorname, d.name),
        al.appointmentdate = COALESCE(al.appointmentdate, a.appointmentdate),
        al.appointmenttime = COALESCE(al.appointmenttime, a.appointmenttime)
  `);

  await pool.query(`
    DELETE FROM appointmentlog
    WHERE patientname IS NULL
      AND doctorname IS NULL
      AND appointmentdate IS NULL
      AND appointmenttime IS NULL
  `);
}

app.listen(PORT, async () => {
  try {
    const connection = await pool.getConnection();
    console.log('Connected to MySQL database:', dbConfig.database);
    connection.release();
    await ensureActivityLogColumns();
    console.log('Activity log columns verified.');
    console.log(`Hospital management server running at http://localhost:${PORT}`);
  } catch (error) {
    console.error('MySQL connection failed:', error.message);
    console.log(`Hospital management server running at http://localhost:${PORT} (database not connected yet)`);
  }
});
