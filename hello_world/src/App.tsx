import { Outlet } from 'react-router-dom';

export function App() {
  return (
    <main className="app-shell">
      <header className="hero">
        <p className="eyebrow">ROAD Stage 1</p>
        <h1>Hello World</h1>
        <p className="lede">
          Minimal Vite, React, and TypeScript scaffold aligned to the ROAD deployment path model.
        </p>
      </header>
      <section className="panel">
        <Outlet />
      </section>
    </main>
  );
}
