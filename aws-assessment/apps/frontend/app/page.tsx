async function getBackendInfo() {
  const base = process.env.BACKEND_URL ?? "http://localhost:8000/api/backend";
  try {
    const res = await fetch(`${base}/info`, { cache: "no-store" });
    if (!res.ok) throw new Error(`status ${res.status}`);
    return await res.json();
  } catch (err) {
    return { error: String(err) };
  }
}

export default async function Home() {
  const info = await getBackendInfo();
  return (
    <main style={{ fontFamily: "system-ui", padding: "2rem" }}>
      <h1>AWS Assessment — Frontend</h1>
      <p>This Next.js app is deployed on AWS and talks to the Python backend.</p>
      <h2>Backend response</h2>
      <pre style={{ background: "#f4f4f4", padding: "1rem", borderRadius: 8 }}>
        {JSON.stringify(info, null, 2)}
      </pre>
    </main>
  );
}
