import React, { useState } from "react";
import "./auth.css";
import logo from "./assets/logo.jpg";

const Register = ({ onSwitchToLogin, onBackToPortal, onRegisterSuccess }) => {
  const [formData, setFormData] = useState({
    fullName: "",
    email: "",
    barangay: "",
    password: "",
    confirmPassword: "",
    termsAgreed: false,
  });
  const [error, setError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleChange = (e) => {
    const { name, value, type, checked } = e.target;
    setFormData((prev) => ({
      ...prev,
      [name]: type === "checkbox" ? checked : value,
    }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");

    if (formData.password !== formData.confirmPassword) {
      setError("Passwords do not match.");
      return;
    }

    if (!formData.termsAgreed) {
      setError("You must agree to the terms before continuing.");
      return;
    }

    setIsSubmitting(true);

    try {
      const response = await fetch("http://127.0.0.1:8000/api/register", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json", // <-- Crucial: tells Laravel to return JSON
        },
        body: JSON.stringify({
          fullName: formData.fullName,
          email: formData.email,
          barangay: formData.barangay,
          password: formData.password,
        }),
      });

      const result = await response.json();

      if (!response.ok) {
        // Handle validation errors or message returned from Laravel
        throw new Error(result.message || "Registration failed.");
      }

      // Success
      if (onRegisterSuccess) onRegisterSuccess();
      if (onSwitchToLogin) onSwitchToLogin();
    } catch (err) {
      setError(err.message || "Unable to create account.");
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
              <h2 className="auth-card-title">Create Account</h2>
              <p className="auth-card-subtitle">
                Join your barangay exchange community
              </p>
            </div>
          </div>

          <form onSubmit={handleSubmit} className="auth-form">
            <div className="auth-input-group">
              <label className="auth-label">Full Name *</label>
              <input
                type="text"
                name="fullName"
                placeholder="e.g. Juan dela Cruz"
                value={formData.fullName}
                onChange={handleChange}
                className="auth-input"
                required
              />
            </div>

            <div className="auth-input-group">
              <label className="auth-label">Email Address *</label>
              <input
                type="email"
                name="email"
                placeholder="you@example.com"
                value={formData.email}
                onChange={handleChange}
                className="auth-input"
                required
              />
            </div>

            <div className="auth-input-group">
              <label className="auth-label">Barangay *</label>
              <select
                name="barangay"
                value={formData.barangay}
                onChange={handleChange}
                className="auth-input"
                required
              >
                <option value="">Select your barangay...</option>
                <option value="Barangay 1">Barangay 1</option>
                <option value="Barangay 2">Barangay 2</option>
                <option value="Barangay 14">Barangay 14</option>
                <option value="San Jose">San Jose</option>
              </select>
            </div>

            <div className="auth-row">
              <div
                className="auth-input-group"
                style={{ flex: 1, marginRight: "10px" }}
              >
                <label className="auth-label">Password *</label>
                <input
                  type="password"
                  name="password"
                  placeholder="Min. 8 characters"
                  value={formData.password}
                  onChange={handleChange}
                  className="auth-input"
                  required
                />
              </div>
              <div className="auth-input-group" style={{ flex: 1 }}>
                <label className="auth-label">Confirm Password *</label>
                <input
                  type="password"
                  name="confirmPassword"
                  placeholder="Repeat password"
                  value={formData.confirmPassword}
                  onChange={handleChange}
                  className="auth-input"
                  required
                />
              </div>
            </div>

            <div className="auth-checkbox-group">
              <input
                type="checkbox"
                name="termsAgreed"
                id="terms"
                checked={formData.termsAgreed}
                onChange={handleChange}
                className="auth-checkbox"
                required
              />
              <label htmlFor="terms" className="auth-checkbox-label">
                I agree to the <strong>Terms of Use</strong> and confirm I
                reside within the listed barangay.
              </label>
            </div>

            {error ? <div className="auth-error">{error}</div> : null}

            <button
              type="submit"
              className="auth-submit"
              disabled={isSubmitting}
            >
              {isSubmitting ? "Creating account..." : "Create Account"}
            </button>
          </form>

          <div className="auth-register-prompt">
            Already have an account?{" "}
            <span className="auth-register-link" onClick={onSwitchToLogin}>
              Sign in
            </span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Register;
