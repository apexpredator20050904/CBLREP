import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
// Tailwind v4 entry (replaces the Vite template stylesheet).
import './tailwind.css'
import App from './App.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
