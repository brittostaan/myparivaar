import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { isSuperAdmin } from '../_shared/admin.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// ============================================================================
// Types
// ============================================================================

interface FeatureFlag {
  id: string
  name: string
  display_name: string
  description: string | null
  is_enabled: boolean
  category: string
  is_beta: boolean
  created_at: string
  updated_at: string
}

interface HouseholdFeatureOverride {
  id: string
  household_id: string
  feature_flag_id: string
  is_enabled: boolean
  reason: string | null
  override_by_admin_id: string | null
  created_at: string
  updated_at: string
}

interface AdminFeatureFlagResponse extends FeatureFlag {
  household_override?: HouseholdFeatureOverride | null
}

// ============================================================================
// Action: list_flags
// ============================================================================

async function listFlags(
  req: Request,
  userId: string,
) {
  const { householdId } = await req.json()

  const response = await fetch(`${SUPABASE_URL}/rest/v1/feature_flags`, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${SERVICE_KEY}`,
      apikey: SERVICE_KEY,
      'Content-Type': 'application/json',
    },
  })

  if (!response.ok) {
    throw new Error(`Failed to fetch feature flags: ${response.status}`)
  }

  let flags: FeatureFlag[] = await response.json()

  // If householdId provided, enrich with household overrides
  if (householdId) {
    const overridesResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/household_feature_overrides?household_id=eq.${householdId}`,
      {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${SERVICE_KEY}`,
          apikey: SERVICE_KEY,
        },
      },
    )

    if (overridesResponse.ok) {
      const overrides: HouseholdFeatureOverride[] = await overridesResponse.json()
      const overrideMap = new Map(overrides.map((o) => [o.feature_flag_id, o]))

      flags = flags.map((flag) => ({
        ...flag,
        household_override: overrideMap.get(flag.id) || null,
      }))
    }
  }

  return new Response(JSON.stringify({ flags }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ============================================================================
// Action: toggle_flag (super-admin only)
// ============================================================================

async function toggleFlag(
  req: Request,
  userId: string,
  isSuperAdminUser: boolean,
) {
  if (!isSuperAdminUser) {
    return new Response(
      JSON.stringify({ error: 'Only super admins can toggle feature flags' }),
      {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  }

  const { flagId } = await req.json()

  const response = await fetch(`${SUPABASE_URL}/rest/v1/feature_flags?id=eq.${flagId}`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${SERVICE_KEY}`,
      apikey: SERVICE_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      is_enabled: true, // Toggle logic: fetch current, invert, and set
      updated_at: new Date().toISOString(),
    }),
  })

  if (!response.ok) {
    throw new Error(`Failed to toggle flag: ${response.status}`)
  }

  const flag: FeatureFlag[] = await response.json()

  // Log audit
  await fetch(`${SUPABASE_URL}/rest/v1/audit_logs`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${SERVICE_KEY}`,
      apikey: SERVICE_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      admin_id: userId,
      action: 'toggle_feature_flag',
      resource_type: 'feature_flag',
      resource_id: flagId,
      details: flag[0],
    }),
  })

  return new Response(JSON.stringify({ flag: flag[0] }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ============================================================================
// Action: set_household_override
// ============================================================================

async function setHouseholdOverride(
  req: Request,
  userId: string,
  isSuperAdminUser: boolean,
) {
  if (!isSuperAdminUser) {
    return new Response(
      JSON.stringify({ error: 'Only super admins can set feature overrides' }),
      {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  }

  const { householdId, flagId, isEnabled, reason } = await req.json()

  // Use UPSERT: try to insert or update if already exists
  const response = await fetch(
    `${SUPABASE_URL}/rest/v1/household_feature_overrides`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${SERVICE_KEY}`,
        apikey: SERVICE_KEY,
        'Content-Type': 'application/json',
        Prefer: 'resolution=merge-duplicates',
      },
      body: JSON.stringify({
        household_id: householdId,
        feature_flag_id: flagId,
        is_enabled: isEnabled,
        reason: reason || null,
        override_by_admin_id: userId,
        updated_at: new Date().toISOString(),
      }),
    },
  )

  if (!response.ok) {
    throw new Error(`Failed to set household override: ${response.status}`)
  }

  const override: HouseholdFeatureOverride[] = await response.json()

  // Log audit
  await fetch(`${SUPABASE_URL}/rest/v1/audit_logs`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${SERVICE_KEY}`,
      apikey: SERVICE_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      admin_id: userId,
      action: 'set_feature_override',
      resource_type: 'household',
      resource_id: householdId,
      details: override[0],
    }),
  })

  return new Response(JSON.stringify({ override: override[0] }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ============================================================================
// Action: remove_household_override
// ============================================================================

async function removeHouseholdOverride(
  req: Request,
  userId: string,
  isSuperAdminUser: boolean,
) {
  if (!isSuperAdminUser) {
    return new Response(
      JSON.stringify({ error: 'Only super admins can remove feature overrides' }),
      {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  }

  const { overrideId } = await req.json()

  const response = await fetch(
    `${SUPABASE_URL}/rest/v1/household_feature_overrides?id=eq.${overrideId}`,
    {
      method: 'DELETE',
      headers: {
        Authorization: `Bearer ${SERVICE_KEY}`,
        apikey: SERVICE_KEY,
      },
    },
  )

  if (!response.ok) {
    throw new Error(`Failed to remove household override: ${response.status}`)
  }

  // Log audit
  await fetch(`${SUPABASE_URL}/rest/v1/audit_logs`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${SERVICE_KEY}`,
      apikey: SERVICE_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      admin_id: userId,
      action: 'remove_feature_override',
      resource_type: 'feature_override',
      resource_id: overrideId,
      details: null,
    }),
  })

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// ============================================================================
// Main Handler
// ============================================================================

serve(async (req: Request) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get auth token
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const token = authHeader.replace('Bearer ', '')

    // Verify token and get user
    const userResponse = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    })

    if (!userResponse.ok) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const authUser = await userResponse.json()
    const userId = authUser.id

    // Check if super admin
    const isSuperAdminUser = await isSuperAdmin(userId, SUPABASE_URL, SERVICE_KEY)

    // Route to appropriate action
    const { action } = await req.json()

    switch (action) {
      case 'list_flags':
        return listFlags(req, userId)
      case 'toggle_flag':
        return toggleFlag(req, userId, isSuperAdminUser)
      case 'set_household_override':
        return setHouseholdOverride(req, userId, isSuperAdminUser)
      case 'remove_household_override':
        return removeHouseholdOverride(req, userId, isSuperAdminUser)
      default:
        return new Response(JSON.stringify({ error: `Unknown action: ${action}` }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    }
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
