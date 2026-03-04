const express = require("express");
const dotenv = require("dotenv");
const cors = require("cors");
const bodyParser = require("body-parser");
const connectDB = require("./db");
const authRoutes = require("./routes/auth");
const profileRoutes = require("./routes/profile");
const aiRouter = require("./routes/aiRoute");
const conversationRoutes = require("./routes/conversationRoute");
const cartRoutes = require ("./routes/cartRoutes");
const pickScoreRoute = require("./routes/pickscoreRoute");
const addressRoute = require("./routes/addressRoutes");

// require("./PickAI").initLaptopVectorStore().then(() => console.log("Warm"));
dotenv.config();
const app = express();

app.use(cors()); // Only once
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ limit: "10mb", extended: true }));

// Log every incoming request
app.use((req, res, next) => {
  console.log(`➡️ ${req.method} ${req.url}`);
  next();
});

// Middleware
app.use(cors({
  origin: '*', // Allow all origins for development
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization', 'ngrok-skip-browser-warning']
}));
app.use(bodyParser.json());

app.use((req, res, next) => {
  console.log(`Incoming: ${req.method} ${req.url}`);
  next();
});

// DB Connection
connectDB().catch(err => {
  console.error("Failed to connect to MongoDB", err);
  process.exit(1);
});

// Routes
app.use("/api/auth", authRoutes);
app.use("/api/profile", profileRoutes);
app.use("/api/ai", aiRouter);
app.use("/api/conversation", conversationRoutes);
app.use("/api/laptops", require("./routes/laptopRoute"));
app.use("/api/cart", cartRoutes);
app.use("/api", pickScoreRoute);
app.use("/address", addressRoute);
app.use("/api/order", require("./routes/orderRoute"));
app.use("/api/payment", require("./routes/paymentRoute"));

const PORT = process.env.PORT || 3000;

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server running on port ${PORT}`);
});

app.get("/", (req, res) => {
  res.json({ message: "PickWise API running..." });
});

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ success: false, message: "Internal Server Error" });
});