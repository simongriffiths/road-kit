export function HomePage() {
  return (
    <div className="stack">
      <div>
        <h2>Bootstrap Ready</h2>
        <p>
          The application is configured to build for
          {' '}
          <code>/ords/{import.meta.env.VITE_UI_BASE_PATH}/ui/{import.meta.env.VITE_APP_NAME}/</code>
          .
        </p>
      </div>
      <dl className="kv">
        <div>
          <dt>App Name</dt>
          <dd>{import.meta.env.VITE_APP_NAME}</dd>
        </div>
        <div>
          <dt>UI Base Path</dt>
          <dd>{import.meta.env.VITE_UI_BASE_PATH}</dd>
        </div>
        <div>
          <dt>API Base URL</dt>
          <dd>{import.meta.env.VITE_ORDS_BASE_URL}</dd>
        </div>
      </dl>
    </div>
  );
}
