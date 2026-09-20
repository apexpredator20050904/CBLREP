import React, { useState } from "react";
import "./auth.css";
import logo from "./assets/logo.jpg";
import { isAdminUser, persistSession } from "./config/community";

const Login = ({ onSwitchToRegister, onBackToPortal, onLoginSuccess }) => {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setIsSubmitting(true);

    try {
      // Relative /api path — forwarded to the Laravel backend by the Vite proxy.
      const response = await fetch("/api/login", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json", // <-- Crucial so Laravel returns JSON
        },
        body: JSON.stringify({ email, password }),
      });

      const result = await response.json();

      if (!response.ok) {
        throw new Error(result.message || "Invalid credentials.");
      }

      // Success: persist the Sanctum session, then hand the user upward.
      persistSession(
        result.user,
        result.access_token,
        isAdminUser(result.user) ? "admin" : "member",
      );
      if (onLoginSuccess) onLoginSuccess(result.user);
    } catch (err) {
      setError(err.message || "Failed to sign in.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="auth-page auth-page--member">
      <div className="auth-sidebar">
        <div>
          <div className="auth-logo-wrap">
            <img src={logo} alt="CBLREP logo" className="auth-logo" />
          </div>
          <h1 className="auth-title">
            Community-Based <br />
            Local Resource <br />
            Exchange Portal
          </h1>
          <p className="auth-description">
            A hyper-local digital commons connecting neighbors, local
            organizations, and grassroots groups for sharing, trading, lending,
            and donating resources within your barangay.
          </p>
        </div>

        <div className="auth-feature-list">
          <div className="auth-feature-item">
            <span className="auth-feature-icon">📦</span>
            <div>
              <strong className="auth-feature-title">
                Post & Discover Resources
              </strong>
              <div className="auth-feature-desc">
                Goods, tools, skills, and shared spaces
              </div>
            </div>
          </div>

          <div className="auth-feature-item">
            <span className="auth-feature-icon">🔄</span>
            <div>
              <strong className="auth-feature-title">
                Multi-Modal Exchange
              </strong>
              <div className="auth-feature-desc">
                Freecycle, barter, lend, or time-bank
              </div>
            </div>
          </div>

          <div className="auth-feature-item">
            <span className="auth-feature-icon">🗺️</span>
            <div>
              <strong className="auth-feature-title">
                Proximity Discovery
              </strong>
              <div className="auth-feature-desc">
                Find resources within your barangay
              </div>
            </div>
          </div>

          <div className="auth-feature-item">
            <span className="auth-feature-icon">🛡️</span>
            <div>
              <strong className="auth-feature-title">Safe & Verified</strong>
              <div className="auth-feature-desc">
                Role-based access and profile verification
              </div>
            </div>
          </div>
        </div>

        <div className="auth-footer">
          © 2026 CBLREP · Barangay-level resource sharing platform
        </div>
      </div>

      <div className="auth-right-content">
        <div className="auth-back-link" onClick={onBackToPortal}>
          ← Back to portal selection
        </div>

        <div className="auth-card">
          <div className="auth-card-header">
            <div className="auth-card-icon">👤</div>
            <div>
              <h2 className="auth-card-title">Community Member</h2>
              <p className="auth-card-subtitle">
                Sign in to your community portal
              </p>
            </div>
          </div>

          <form onSubmit={handleSubmit} className="auth-form">
            <div className="auth-input-group">
              <label className="auth-label">Email Address</label>
              <input
                type="email"
                placeholder="you@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="auth-input"
                required
              />
            </div>

            <div className="auth-input-group">
              <label className="auth-label">Password</label>
              <input
                type="password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="auth-input"
                required
              />
            </div>

            {error ? <div className="auth-error">{error}</div> : null}

            <button
              type="submit"
              className="auth-submit"
              disabled={isSubmitting}
            >
              {isSubmitting ? "Signing in..." : "Sign In as Community Member"}
            </button>
          </form>

          <div className="auth-register-prompt">
            No account yet?{" "}
            <span className="auth-register-link" onClick={onSwitchToRegister}>
              Register here
            </span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Login;
