import React, { useState } from "react";
import "./auth.css";
import logo from "./assets/logo.jpg";
import { persistSession } from "./config/community";

const AdminLogin = ({ onBackToPortal, onAdminLoginSuccess }) => {
  const [formData, setFormData] = useState({
    email: "admin@cblrep.ph",
    password: "",
    adminCode: "",
  });
  const [error, setError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setIsSubmitting(true);

    try {
      const response = await fetch("/api/admin-login", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({
          email: formData.email,
          password: formData.password,
          adminCode: formData.adminCode,
        }),
      });

      const result = await response.json();
      if (!response.ok) {
        throw new Error(result.message || "Admin login failed.");
      }

      // Persist the Sanctum token so AdminApp's Bearer-token apiFetch works.
      persistSession(result.user, result.access_token, "admin");
      onAdminLoginSuccess(result.user);
    } catch (err) {
      setError(err.message || "Unable to sign in as admin.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="auth-page auth-page--admin">
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
            <div className="auth-header-left">
              <div className="auth-card-admin-icon">🛡️</div>
              <div>
                <h2 className="auth-card-title">System Administrator</h2>
                <p className="auth-card-subtitle">
                  Restricted access — verified admins only
                </p>
              </div>
            </div>
            <div className="auth-admin-badge">ADMIN</div>
          </div>

          <div className="auth-warning-box">
            <span className="auth-warning-icon">🔒</span>
            <span className="auth-warning-text">
              Administrator accounts are restricted to verified system
              personnel. All login attempts are logged and monitored.
            </span>
          </div>

          <div className="auth-demo-box">
            <div className="auth-demo-title">Demo credentials</div>
            <div className="auth-demo-text">Email: admin@cblrep.ph</div>
            <div className="auth-demo-text">Password: admin123</div>
          </div>

          <form onSubmit={handleSubmit} className="auth-form">
            <div className="auth-input-group">
              <label className="auth-label">Administrator Email</label>
              <input
                type="email"
                name="email"
                value={formData.email}
                onChange={handleChange}
                className="auth-input"
                required
              />
            </div>

            <div className="auth-input-group">
              <label className="auth-label">Password</label>
              <input
                type="password"
                name="password"
                placeholder="Administrator password"
                value={formData.password}
                onChange={handleChange}
                className="auth-input"
                required
              />
            </div>

            <div className="auth-input-group">
              <label className="auth-label">
                Admin Access Code{" "}
                <span style={{ fontWeight: "400", color: "#c6bbdf" }}>
                  (optional for demo)
                </span>
              </label>
              <input
                type="text"
                name="adminCode"
                placeholder="6-digit code from authenticator"
                value={formData.adminCode}
                onChange={handleChange}
                className="auth-input"
              />
            </div>

            {error ? <div className="auth-error">{error}</div> : null}

            <button
              type="submit"
              className="auth-submit"
              disabled={isSubmitting}
            >
              {isSubmitting ? "Signing in..." : "Sign In as Administrator"}
            </button>
          </form>

          <div className="auth-forgot-password-prompt">
            Forgot administrator password?
          </div>
        </div>
      </div>
    </div>
  );
};

export default AdminLogin;
