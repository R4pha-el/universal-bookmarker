export type ServerConfiguration = { url: string; serviceKey: string };
type Fetcher = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { ...cors, "Content-Type": "application/json" } });

/** Identity comes only from GoTrue verification, never a caller-supplied account ID. */
export async function handleAccountAction(request: Request, action: "delete" | "cleanup", configuration: ServerConfiguration, fetcher: Fetcher = fetch): Promise<Response> {
  if (request.method === "OPTIONS") return new Response(null, { headers: cors });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ") || authorization.length < 8) return json({ error: "authentication_required" }, 401);
  if (!configuration.url.startsWith("https://") || !configuration.serviceKey) return json({ error: "service_not_configured" }, 503);
  const base = configuration.url.replace(/\/$/, "");
  const admin = { apikey: configuration.serviceKey, Authorization: `Bearer ${configuration.serviceKey}`, "Content-Type": "application/json" };
  async function checked(path: string, init: RequestInit = {}): Promise<Response> {
    const response = await fetcher(base + path, { ...init, headers: { ...admin, ...init.headers } });
    if (!response.ok) throw new Error("service_request_failed");
    return response;
  }
  async function remove(paths: string[]): Promise<void> {
    if (paths.length) await checked("/storage/v1/object/originals", { method: "DELETE", body: JSON.stringify({ prefixes: paths }) });
  }
  try {
    const verified = await fetcher(base + "/auth/v1/user", { headers: { apikey: configuration.serviceKey, Authorization: authorization } });
    if (!verified.ok) return json({ error: "authentication_required" }, 401);
    const account = await verified.json() as { id?: string };
    if (!account.id || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(account.id)) return json({ error: "authentication_required" }, 401);
    const owner = account.id.toLowerCase();
    if (action === "cleanup") {
      // One bounded batch per request. Later foreground syncs continue draining.
      const result = await checked(`/rest/v1/original_cleanup_jobs?owner_id=eq.${owner}&select=storage_path&limit=100`);
      const jobs = await result.json() as { storage_path: string }[];
      const paths = jobs.map(job => job.storage_path);
      if (paths.some(path => !path.startsWith(owner + "/"))) throw new Error("invalid_cleanup_scope");
      await remove(paths);
      for (const path of paths) {
        await checked(`/rest/v1/original_cleanup_jobs?owner_id=eq.${owner}&storage_path=eq.${encodeURIComponent(path)}`, { method: "DELETE" });
      }
      return json({ removed: paths.length });
    }
    // Shares the account revision lock with mutations and original inserts. Once
    // committed, new writes are denied while removal is retried to completion.
    await checked("/rest/v1/rpc/begin_account_deletion", { method: "POST", headers: { Authorization: authorization }, body: "{}" });
    async function removeTree(prefix: string, depth = 0): Promise<void> {
      if (depth > 4) throw new Error("invalid_storage_tree");
      for (;;) {
        const result = await checked("/storage/v1/object/list/originals", { method: "POST", body: JSON.stringify({ prefix, limit: 100, offset: 0, sortBy: { column: "name", order: "asc" } }) });
        const entries = await result.json() as { name: string; id?: string | null }[];
        if (!entries.length) break;
        const files: string[] = [];
        for (const entry of entries) {
          if (!entry.name || entry.name.includes("/") || entry.name === "." || entry.name === "..") throw new Error("invalid_storage_name");
          const path = prefix + "/" + entry.name;
          if (entry.id) files.push(path); else await removeTree(path, depth + 1);
        }
        await remove(files);
      }
    }
    await removeTree(owner);
    await checked("/auth/v1/admin/users/" + owner, { method: "DELETE" });
    return json({ deleted: true });
  } catch {
    // Do not return provider bodies or credentials. A partially deleted account
    // stays frozen and can retry the same action without accepting new data.
    return json({ error: "account_action_incomplete", message: "Please retry to finish this account operation." }, 502);
  }
}
