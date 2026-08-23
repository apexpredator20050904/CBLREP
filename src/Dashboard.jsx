import React, { useEffect, useState } from "react";
import "./auth.css";

const Dashboard = ({ user: initialUser, onLogout }) => {
  const [user, setUser] = useState(initialUser);
  const [loading, setLoading] = useState(!initialUser);

  useEffect(() => {
    // If user wasn't passed via props, fetch it using the saved token
    if (!initialUser) {
      const fetchUser = async () => {
        const token = localStorage.getItem("token");
        if (!token) {
          onLogout();
          return;
        }

        try {
          const res = await fetch("http://127.0.0.1:8000/api/user", {
            headers: {
              Accept: "application/json",
              Authorization: `Bearer ${token}`,
            },
          });
          const data = await res.json();
          if (res.ok) {
            setUser(data);
          } else {
            onLogout();
          }
        } catch (err) {
          console.error(err);
        } finally {
          setLoading(false);
        }
      };
      fetchUser();
    }
  }, [initialUser, onLogout]);

  if (loading) {
    return (
      <div style={{ padding: "50px", textAlign: "center" }}>
        Loading dashboard...
      </div>
    );
  }

  // Safe fallback for initials generation to prevent crashes
  const getInitials = () => {
    const name = user?.fullName || user?.name || "Member";
    return name
      .split(" ")
      .map((part) => part[0])
      .slice(0, 2)
      .join("")
      .toUpperCase();
  };

  return (
    <div
      style={{
        padding: "40px",
        fontFamily: "sans-serif",
        background: "#f4f7f6",
        minHeight: "100vh",
      }}
    >
      <div
        style={{
          maxWidth: "800px",
          margin: "0 auto",
          background: "white",
          padding: "30px",
          borderRadius: "12px",
          boxShadow: "0 4px 12px rgba(0,0,0,0.05)",
        }}
      >
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            borderBottom: "1px solid #eee",
            paddingBottom: "20px",
            marginBottom: "20px",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: "15px" }}>
            <div
              style={{
                width: "50px",
                height: "50px",
                background: "#2d6a4f",
                color: "white",
                borderRadius: "50%",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontWeight: "bold",
                fontSize: "18px",
              }}
            >
              {getInitials()}
            </div>
            <div>
              <h2 style={{ margin: 0 }}>
                Welcome back, {user?.fullName || user?.name || "Member"}! 👋
              </h2>
              <p style={{ margin: "5px 0 0", color: "#666", fontSize: "14px" }}>
                {user?.email}
              </p>
            </div>
          </div>
          <button
            onClick={onLogout}
            style={{
              padding: "8px 16px",
              background: "#dc3545",
              color: "white",
              border: "none",
              borderRadius: "6px",
              cursor: "pointer",
            }}
          >
            Sign Out
          </button>
        </div>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "1fr 1fr",
            gap: "20px",
          }}
        >
          <div
            style={{
              background: "#f8f9fa",
              padding: "20px",
              borderRadius: "8px",
            }}
          >
            <h4>Profile Information</h4>
            <p>
              <strong>Barangay:</strong>{" "}
              {user?.barangay_or_location || user?.barangay || "Not specified"}
            </p>
            <p>
              <strong>Role:</strong> {user?.role || "user"}
            </p>
          </div>

          <div
            style={{
              background: "#f8f9fa",
              padding: "20px",
              borderRadius: "8px",
            }}
          >
            <h4>Community Status</h4>
            <p>
              <strong>Time Bank Credits:</strong> ⏰{" "}
              {user?.time_bank_credits || 0} hrs
            </p>
            <p>
              <strong>Verification Status:</strong>{" "}
              {user?.is_verified
                ? "✅ Verified Resident"
                : "⏳ Pending Verification"}
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
