import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

async function test() {
  console.log("Testing getUserByEmail existance...");
  console.log("typeof getUserByEmail:", typeof supabase.auth.admin.getUserByEmail);
  
  try {
    const { data: user, error } = await supabase.auth.admin.getUserByEmail("feranmioresajo@gmail.com");
    console.log("Result:", { user, error });
  } catch (e) {
    console.log("Error:", e.message);
  }
}

test();
