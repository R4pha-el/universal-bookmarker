import { handleAccountAction } from "../_shared/account-service.ts";

Deno.serve((request: Request) => handleAccountAction(request, "cleanup", {
  url: Deno.env.get("SUPABASE_URL") ?? "",
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
}));
