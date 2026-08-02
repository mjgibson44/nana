import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { applyTheme, loadThemePref } from './theme';
import './styles.css';

// Apply the saved theme before the first paint, so the page never flashes
// the wrong scheme.
applyTheme(loadThemePref());

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
