/**
 * import-csv
 *
 * Parses, validates, and commits CSV data (transactions or budgets) for a household.
 *
 * POST /functions/v1/import-csv
 * Header:  Authorization: Bearer <firebase_id_token>
 * Body:
 *   {
 *     "type":   "expenses" | "budgets",
 *     "action": "preview"  | "commit",
 *     "csv":    "<raw CSV text>"
 *   }
 *
 * Expense CSV columns:   date (YYYY-MM-DD), amount, category, description, notes (opt)
 * Budget CSV columns:    category, amount, month (YYYY-MM)
 *
 * preview → validates rows, returns results, writes nothing to DB
 * commit  → rejects if any errors present, inserts rows + creates import_batch
 *
 * Budget commit uses upsert on (household_id, category, month) per PRD:
 * "Replace existing budgets on import"
 *
 * Tables used (app schema):
 *   app.transactions, app.budgets, app.import_batches
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parse as parseCsv } from "https://deno.land/std@0.208.0/csv/mod.ts";
import { verifyFirebaseToken } from "../_shared/firebase.ts";

// ── Constants ───────────────────────────────────────────────────────────────
const MAX_ROWS = 500;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

// ── Supabase client (service role — never sent to client) ───────────────────
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {
    auth: { persistSession: false },
    db: { schema: "app" },
  },
);

// ── Helpers ─────────────────────────────────────────────────────────────────
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ── Types ────────────────────────────────────────────────────────────────────
interface RowError {
  row: number;
  field: string;
  message: string;
}

interface ValidatedExpenseRow {
  date: string;
  amount: number;
  category: string;
  description: string;
  notes: string | null;
}

interface ValidatedBudgetRow {
  category: string;
  amount: number;
  month: string;
}

// ── Validators ───────────────────────────────────────────────────────────────
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MONTH_RE    = /^\d{4}-(0[1-9]|1[0-2])$/;

function isValidIsoDate(s: string): boolean {
  if (!ISO_DATE_RE.test(s)) return false;
  const d = new Date(s + "T00:00:00Z");
  return !isNaN(d.getTime());
}

/**
 * Parses an amount string.
 * Strips thousands commas, requires positive value, max 2 decimal places.
 * Returns null if invalid.
 */
function parseAmount(raw: string): number | null {
  const s = raw.trim().replace(/,/g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return null;
  const n = parseFloat(s);
  if (!isFinite(n) || n <= 0 || n > 99_999_999.99) return null;
  return n;
}

function str(row: Record<string, string>, key: string): string {
  return (row[key] ?? "").trim();
}

// ── Row validators ───────────────────────────────────────────────────────────
function validateExpenseRows(rawRows: Record<string, string>[]): {
  valid: ValidatedExpenseRow[];
  errors: RowError[];
} {
  const valid: ValidatedExpenseRow[] = [];
  const errors: RowError[] = [];

  for (let i = 0; i < rawRows.length; i++) {
    const row = rawRows[i];
    const rowNum = i + 2; // +1 for header, +1 for 1-based index
    const rowErrors: RowError[] = [];

    const date = str(row, "date");
    if (!date) {
      rowErrors.push({ row: rowNum, field: "date", message: "Required" });
    } else if (!isValidIsoDate(date)) {
      rowErrors.push({ row: rowNum, field: "date", message: "Must be YYYY-MM-DD" });
    }

    const amountRaw = str(row, "amount");
    const amount = amountRaw ? parseAmount(amountRaw) : null;
    if (!amountRaw) {
      rowErrors.push({ row: rowNum, field: "amount", message: "Required" });
    } else if (amount === null) {
      rowErrors.push({
        row: rowNum,
        field: "amount",
        message: "Must be a positive number with at most 2 decimal places (max 99,999,999.99)",
      });
    }

    const category = str(row, "category");
    if (!category) {
      rowErrors.push({ row: rowNum, field: "category", message: "Required" });
    } else if (category.length > 50) {
      rowErrors.push({ row: rowNum, field: "category", message: "Max 50 characters" });
    }

    const description = str(row, "description");
    if (!description) {
      rowErrors.push({ row: rowNum, field: "description", message: "Required" });
    } else if (description.length > 200) {
      rowErrors.push({ row: rowNum, field: "description", message: "Max 200 characters" });
    }

    const notes = str(row, "notes") || null;
    if (notes && notes.length > 500) {
      rowErrors.push({ row: rowNum, field: "notes", message: "Max 500 characters" });
    }

    if (rowErrors.length > 0) {
      errors.push(...rowErrors);
    } else {
      valid.push({ date, amount: amount!, category, description, notes });
    }
  }

  return { valid, errors };
}

function validateBudgetRows(rawRows: Record<string, string>[]): {
  valid: ValidatedBudgetRow[];
  errors: RowError[];
} {
  const valid: ValidatedBudgetRow[] = [];
  const errors: RowError[] = [];

  for (let i = 0; i < rawRows.length; i++) {
    const row = rawRows[i];
    const rowNum = i + 2;
    const rowErrors: RowError[] = [];

    const category = str(row, "category");
    if (!category) {
      rowErrors.push({ row: rowNum, field: "category", message: "Required" });
    } else if (category.length > 50) {
      rowErrors.push({ row: rowNum, field: "category", message: "Max 50 characters" });
    }

    const amountRaw = str(row, "amount");
    const amount = amountRaw ? parseAmount(amountRaw) : null;
    if (!amountRaw) {
      rowErrors.push({ row: rowNum, field: "amount", message: "Required" });
    } else if (amount === null) {
      rowErrors.push({
        row: rowNum,
        field: "amount",
        message: "Must be a positive number with at most 2 decimal places (max 99,999,999.99)",
      });
    }

    const month = str(row, "month");
    if (!month) {
      rowErrors.push({ row: rowNum, field: "month", message: "Required" });
    } else if (!MONTH_RE.test(month)) {
      rowErrors.push({ row: rowNum, field: "month", message: "Must be YYYY-MM (e.g. 2026-03)" });
    }

    if (rowErrors.length > 0) {
      errors.push(...rowErrors);
    } else {
      valid.push({ category, amount: amount!, month });
    }
  }

  return { valid, errors };
}

// ── Handler ──────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // ── 1. Authenticate ──────────────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  let uid: string;
  try {
    const claims = await verifyFirebaseToken(authHeader.slice(7).trim());
    uid = claims.uid;
  } catch {
    return json({ error: "Invalid or expired token" }, 401);
  }

  // ── 2. Resolve user ──────────────────────────────────────────────────────
  const { data: user, error: userErr } = await supabase
    .from("users")
    .select("id, household_id")
    .eq("firebase_uid", uid)
    .is("deleted_at", null)
    .maybeSingle();

  if (userErr) {
    console.error("user lookup:", userErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!user) {
    return json({ error: "User not found" }, 404);
  }
  if (!user.household_id) {
    return json({ error: "User does not belong to a household" }, 403);
  }

  // ── 3. Resolve household ─────────────────────────────────────────────────
  const { data: household, error: hhErr } = await supabase
    .from("households")
    .select("id, suspended")
    .eq("id", user.household_id)
    .is("deleted_at", null)
    .maybeSingle();

  if (hhErr) {
    console.error("household lookup:", hhErr);
    return json({ error: "Internal server error" }, 500);
  }
  if (!household) {
    return json({ error: "Household not found" }, 404);
  }
  if (household.suspended) {
    return json({ error: "Household is suspended" }, 403);
  }

  const householdId = household.id as string;
  const userId = user.id as string;

  // ── 4. Parse request body ────────────────────────────────────────────────
  let body: { type?: unknown; action?: unknown; csv?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { type: importType, action: importAction, csv: csvInput } = body;

  if (importType !== "expenses" && importType !== "budgets") {
    return json({ error: 'type must be "expenses" or "budgets"' }, 400);
  }
  if (importAction !== "preview" && importAction !== "commit") {
    return json({ error: 'action must be "preview" or "commit"' }, 400);
  }
  if (typeof csvInput !== "string" || csvInput.trim().length === 0) {
    return json({ error: "csv must be a non-empty string" }, 400);
  }

  // ── 5. Parse CSV ─────────────────────────────────────────────────────────
  let rawRows: Record<string, string>[];
  try {
    rawRows = parseCsv(csvInput.trim(), {
      skipFirstRow: true,
    }) as Record<string, string>[];
  } catch (err) {
    return json({
      error: `CSV parse error: ${err instanceof Error ? err.message : "invalid format"}`,
    }, 400);
  }

  if (rawRows.length === 0) {
    return json({ error: "CSV contains no data rows" }, 400);
  }
  if (rawRows.length > MAX_ROWS) {
    return json({ error: `CSV exceeds the maximum of ${MAX_ROWS} rows per import` }, 400);
  }

  // ── 6. Validate rows ─────────────────────────────────────────────────────
  let validExpenses: ValidatedExpenseRow[] = [];
  let validBudgets: ValidatedBudgetRow[] = [];
  let errors: RowError[];

  if (importType === "expenses") {
    ({ valid: validExpenses, errors } = validateExpenseRows(rawRows));
  } else {
    ({ valid: validBudgets, errors } = validateBudgetRows(rawRows));
  }

  const validRows = importType === "expenses" ? validExpenses : validBudgets;
  const validCount = validRows.length;
  const errorCount = errors.length;

  // ── 7. Preview (no DB writes) ────────────────────────────────────────────
  if (importAction === "preview") {
    return json({
      action: "preview",
      type: importType,
      valid_rows: validRows,
      errors,
      valid_count: validCount,
      error_count: errorCount,
    });
  }

  // ── 8. Commit ────────────────────────────────────────────────────────────
  // All rows must be valid before committing.
  if (errorCount > 0) {
    return json({
      error: "CSV contains validation errors. Resolve all errors before committing.",
      errors,
      error_count: errorCount,
    }, 422);
  }

  // Create import_batch record
  const { data: batch, error: batchErr } = await supabase
    .from("import_batches")
    .insert({
      household_id: householdId,
      imported_by_user_id: userId,
      type: importType,
      row_count: validCount,
      status: "completed",
    })
    .select("id")
    .single();

  if (batchErr || !batch) {
    console.error("import_batches insert:", batchErr);
    return json({ error: "Internal server error" }, 500);
  }

  const batchId = batch.id as string;

  // Insert/upsert rows
  if (importType === "expenses") {
    // Expense rows go into app.transactions
    const rows = validExpenses.map((r) => ({
      household_id: householdId,
      imported_by_user_id: userId,
      import_batch_id: batchId,
      date: r.date,
      amount: r.amount,
      category: r.category,
      description: r.description,
      notes: r.notes,
      source: "csv",
      status: "approved", // CSV rows are pre-approved; no pending review needed
    }));

    const { error: insertErr } = await supabase.from("transactions").insert(rows);

    if (insertErr) {
      await supabase.from("import_batches").delete().eq("id", batchId);
      console.error("transactions insert:", insertErr);
      return json({ error: "Internal server error" }, 500);
    }
  } else {
    // Budgets: upsert on (household_id, category, month)
    // PRD: "Replace existing budgets on import"
    const rows = validBudgets.map((r) => ({
      household_id: householdId,
      imported_by_user_id: userId,
      import_batch_id: batchId,
      category: r.category,
      amount: r.amount,
      month: r.month,
    }));

    const { error: upsertErr } = await supabase
      .from("budgets")
      .upsert(rows, {
        onConflict: "household_id,category,month",
        ignoreDuplicates: false,
      });

    if (upsertErr) {
      await supabase.from("import_batches").delete().eq("id", batchId);
      console.error("budgets upsert:", upsertErr);
      return json({ error: "Internal server error" }, 500);
    }
  }

  return json({
    action: "commit",
    type: importType,
    imported: validCount,
    batch_id: batchId,
  }, 201);
});
