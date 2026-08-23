import React, { useState } from "react";
import "./App.css";
import logo from "./assets/logo.jpg";
import reactLogo from "./assets/react.svg";
import viteLogo from "./assets/vite.svg";

import Login from "./Login";
import Register from "./Register";
import AdminLogin from "./AdminLogin";
import Dashboard from "./Dashboard";

const App = () => {
  const [currentView, setCurrentView] = useState("landing");
  const [user, setUser] = useState(null);

  const handleLoginSuccess = (loggedInUser) => {
    setUser(loggedInUser);
    setCurrentView("dashboard");
  };

  const handleLogout = () => {
    setUser(null);
    setCurrentView("landing");
  };

  if (currentView === "member-login") {
    return (
      <Login
        onSwitchToRegister={() => setCurrentView("member-register")}
        onBackToPortal={() => setCurrentView("landing")}
        onLoginSuccess={handleLoginSuccess}
      />
    );
  }

  if (currentView === "member-register") {
    return (
      <Register
        onSwitchToLogin={() => setCurrentView("member-login")}
        onBackToPortal={() => setCurrentView("landing")}
        onRegisterSuccess={() => setCurrentView("member-login")}
      />
    );
  }

  if (currentView === "admin-login") {
    return (
      <AdminLogin
        onBackToPortal={() => setCurrentView("landing")}
        onAdminLoginSuccess={handleLoginSuccess}
      />
    );
  }

  if (currentView === "dashboard") {
    return <Dashboard user={user} onLogout={handleLogout} />;
  }

  return (
    <div className="hero-page">
      <div className="hero-container">
        <div className="logo-wrap" aria-hidden>
          <img src={logo} alt="CBLREP logo" className="logo-img" />
        </div>

        <h1 className="hero-title">
          Community-Based
          <br />
          Local Resource Exchange Portal
        </h1>

        <p className="hero-subtitle">
          CBLREP · Barangay-level hyper-local resource sharing
        </p>

        <div className="sign-in-label">SIGN IN AS</div>

        <div className="cards">
          <section className="card member">
            <div>
              <div className="role-icon member-icon" aria-hidden>
                <img src={reactLogo} alt="member icon" width="28" height="28" />
              </div>
              <div className="role-title">Community Member</div>
              <div className="role-desc">
                Browse, post, and exchange resources with your neighbors
              </div>
            </div>
            <button
              className="btn member-btn"
              aria-label="Member Login"
              onClick={() => setCurrentView("member-login")}
            >
              Member Login →
            </button>
          </section>

          <section className="card admin">
            <div>
              <div className="role-icon admin-icon" aria-hidden>
                <img src={viteLogo} alt="admin icon" width="28" height="28" />
              </div>
              <div className="role-title">System Administrator</div>
              <div className="role-desc">
                Manage users, listings, moderation and platform reports
              </div>
            </div>
            <button
              className="btn admin-btn"
              aria-label="Admin Login"
              onClick={() => setCurrentView("admin-login")}
            >
              Admin Login →
            </button>
          </section>
        </div>

        <div className="hero-footer">
          Community-Based Local Resource Exchange Portal · CBLREP © 2026
        </div>
      </div>
    </div>
  );
};

export default App;
