import { FormEvent, useEffect, useState } from 'react';
import { Check } from 'lucide-react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';

import { loginRequest } from '../api/auth';
import { AppMark } from '../components/road/AppMark';
import { Notice } from '../components/road/Notice';
import { Button } from '../components/ui/button';
import { Input } from '../components/ui/input';
import { Label } from '../components/ui/label';
import { app, pageTitle } from '../config/app';
import { isApiError } from '../types/api';
import { getToken, setToken } from '../utils/auth';

// Sign in (spec-patch-18 section 7.1). Outside the app shell: an app panel on the left and the form
// on the right, stacked below 768 px. The scaffold is the only profile this build signs in with.
export function LoginPage() {
  const location = useLocation();
  const navigate = useNavigate();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => { document.title = pageTitle('Sign in'); }, []);

  if (getToken()) {
    return <Navigate replace to="/" />;
  }

  const from = typeof location.state?.from === 'string' ? location.state.from : '/';

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setErrorMessage(null);
    try {
      const response = await loginRequest(username, password);
      setToken(response.access_token);
      navigate(from, { replace: true });
    } catch (error) {
      setErrorMessage(isApiError(error) ? error.message : 'Sign in failed unexpectedly.');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="flex min-h-screen flex-col bg-background text-foreground md:flex-row">
      <section className="flex flex-col gap-10 bg-primary-strong px-8 py-10 text-primary-foreground md:w-1/2 md:px-14 md:py-12">
        <AppMark inverted />
        <div className="flex max-w-md flex-1 flex-col justify-center gap-4">
          <h1 className="m-0 text-balance text-4xl font-semibold leading-tight tracking-tight">{app.description}</h1>
          <ul className="m-0 mt-2 flex list-none flex-col gap-3 p-0 text-sm leading-relaxed">
            {app.points.map((p) => (
              <li className="flex items-start gap-3" key={p}>
                <Check aria-hidden="true" className="mt-0.5 size-4 shrink-0" />
                <span>{p}</span>
              </li>
            ))}
          </ul>
        </div>
        <p className="m-0 text-xs opacity-80">Built on road-kit: React, ORDS and PL/SQL on Oracle Autonomous Database.</p>
      </section>

      <section className="flex flex-1 items-center justify-center px-6 py-10">
        <form className="flex w-full max-w-sm flex-col gap-4" onSubmit={handleSubmit}>
          <div>
            <h2 className="m-0 text-2xl font-semibold tracking-tight">Sign in</h2>
            <p className="mt-1.5 text-sm text-muted-foreground">Use the account your administrator gave you.</p>
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="si-user">User name</Label>
            <Input autoComplete="username" id="si-user" name="username" onChange={(e) => setUsername(e.target.value)} required value={username} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="si-pass">Password</Label>
            <Input autoComplete="current-password" id="si-pass" name="password" onChange={(e) => setPassword(e.target.value)} required type="password" value={password} />
          </div>
          {errorMessage ? <Notice kind="error">{errorMessage}</Notice> : null}
          <Button className="h-10 text-sm" disabled={submitting} type="submit">{submitting ? 'Signing in…' : 'Sign in'}</Button>
          <span className="self-start rounded-full border border-dashed border-border-strong px-2.5 py-1 text-xs text-muted-foreground">
            Development sign-in
          </span>
        </form>
      </section>
    </main>
  );
}
