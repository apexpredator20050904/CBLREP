import express from "express";
import cors from "cors";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const dbPath = path.join(__dirname, "data", "db.json");
const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

const ensureDatabase = () => {
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  if (!fs.existsSync(dbPath)) {
    const defaultData = {
      users: [
        {
          id: 1,
          fullName: "Maria Santos",
          email: "maria.santos@cblrep.ph",
          barangay: "Barangay 14",
          password: "member123",
          role: "member",
        },
        {
          id: 2,
          fullName: "System Administrator",
          email: "admin@cblrep.ph",
          barangay: "Barangay 1",
          password: "admin123",
          role: "admin",
        },
      ],
      resources: [
        {
          id: 1,
          title: "Portable Water Pump",
          category: "Tools",
          location: "Barangay 14",
          postedBy: "Maria Santos",
          status: "available",
        },
        {
          id: 2,
          title: "Community Event Tent",
          category: "Events",
          location: "Barangay 14",
          postedBy: "Liza Rios",
          status: "available",
        },
        {
          id: 3,
          title: "Rice Milling Service",
          category: "Services",
          location: "Barangay 14",
          postedBy: "Ramon Cruz",
          status: "requested",
        },
      ],
      activities: [
        {
          id: 1,
          icon: "📦",
          text: "You posted a new resource offer",
          time: "2 hours ago",
        },
        {
          id: 2,
          icon: "🔄",
          text: "A neighbor requested your recycling tools",
          time: "5 hours ago",
        },
        {
          id: 3,
          icon: "🤝",
          text: "Barangay 14 meetup was confirmed",
          time: "1 day ago",
        },
      ],
    };

    fs.writeFileSync(dbPath, JSON.stringify(defaultData, null, 2), "utf8");
  }
};

const readDatabase = () => {
  ensureDatabase();
  const file = fs.readFileSync(dbPath, "utf8");
  return JSON.parse(file);
};

const writeDatabase = (data) => {
  fs.writeFileSync(dbPath, JSON.stringify(data, null, 2), "utf8");
};

const sanitizeUser = (user) => {
  if (!user) return null;
  const { password, ...safeUser } = user;
  return safeUser;
};

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, message: "CBLREP backend is running" });
});

app.post("/api/register", (req, res) => {
  const { fullName, email, barangay, password } = req.body || {};

  if (!fullName || !email || !barangay || !password) {
    return res.status(400).json({ message: "All fields are required." });
  }

  if (password.length < 6) {
    return res
      .status(400)
      .json({ message: "Password must be at least 6 characters." });
  }

  const db = readDatabase();
  const existingUser = db.users.find(
    (user) => user.email.toLowerCase() === String(email).toLowerCase(),
  );

  if (existingUser) {
    return res
      .status(409)
      .json({ message: "An account with that email already exists." });
  }

  const newUser = {
    id: Date.now(),
    fullName,
    email: email.toLowerCase(),
    barangay,
    password,
    role: "member",
  };

  db.users.push(newUser);
  writeDatabase(db);

  return res.status(201).json({
    message: "Account created successfully.",
    user: sanitizeUser(newUser),
  });
});

app.post("/api/login", (req, res) => {
  const { email, password } = req.body || {};

  if (!email || !password) {
    return res
      .status(400)
      .json({ message: "Email and password are required." });
  }

  const db = readDatabase();
  const user = db.users.find(
    (entry) =>
      entry.email.toLowerCase() === String(email).toLowerCase() &&
      entry.password === password,
  );

  if (!user) {
    return res.status(401).json({ message: "Invalid email or password." });
  }

  return res.json({
    message: "Login successful.",
    user: sanitizeUser(user),
  });
});

app.post("/api/admin-login", (req, res) => {
  const { email, password } = req.body || {};

  if (!email || !password) {
    return res
      .status(400)
      .json({ message: "Email and password are required." });
  }

  const db = readDatabase();
  const admin = db.users.find(
    (user) =>
      user.email.toLowerCase() === String(email).toLowerCase() &&
      user.password === password &&
      user.role === "admin",
  );

  if (!admin) {
    return res
      .status(401)
      .json({ message: "Invalid administrator credentials." });
  }

  return res.json({
    message: "Admin login successful.",
    user: sanitizeUser(admin),
  });
});

app.get("/api/dashboard", (req, res) => {
  const email = String(req.query.email || "").toLowerCase();
  const db = readDatabase();

  const user = db.users.find((entry) => entry.email.toLowerCase() === email);

  if (!user) {
    return res.status(404).json({ message: "User not found." });
  }

  const stats = {
    itemsAvailable: db.resources.length,
    activeExchanges: db.resources.filter(
      (resource) => resource.status === "requested",
    ).length,
    membersNearby: Math.max(12, db.users.length * 3),
    timeBankCredits: user.role === "admin" ? 18.5 : 4.8,
  };

  return res.json({
    stats,
    resources: db.resources,
    activities: db.activities,
  });
});

app.listen(PORT, () => {
  console.log(`CBLREP backend running on http://localhost:${PORT}`);
});
