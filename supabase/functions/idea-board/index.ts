import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyFirebaseToken } from '../_shared/firebase.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

/**
 * Idea Board — single endpoint handling all CRUD actions.
 *
 * Requires admin (staff_role IS NOT NULL or role = 'super_admin').
 *
 * Body:
 *   action: 'list' | 'create' | 'update' | 'delete' | 'add_comment' | 'delete_comment'
 *   ...params depending on action
 */
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  try {
    if (req.method !== 'POST') {
      return json({ error: 'Method not allowed' }, 405)
    }

    // ── Auth ────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return json({ error: 'Missing authorization header' }, 401)
    }

    const idToken = authHeader.split('Bearer ')[1]
    const decoded = await verifyFirebaseToken(idToken)
    if (!decoded?.uid) {
      return json({ error: 'Invalid auth token' }, 401)
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: 'app' },
    })

    // Resolve user and check admin
    const { data: user, error: userErr } = await supabase
      .from('users')
      .select('id, role, staff_role')
      .eq('firebase_uid', decoded.uid)
      .single()

    if (userErr || !user) {
      return json({ error: 'User not found' }, 404)
    }

    const isAdmin =
      user.role === 'super_admin' ||
      user.staff_role === 'super_admin' ||
      (user.staff_role != null && user.staff_role !== '')

    if (!isAdmin) {
      return json({ error: 'Admin access required' }, 403)
    }

    // ── Router ──────────────────────────────────────────────────────────
    const body = await req.json()
    const { action } = body

    switch (action) {
      case 'list':
        return await handleList(supabase, json)

      case 'create':
        return await handleCreate(supabase, user.id, body, json)

      case 'update':
        return await handleUpdate(supabase, body, json)

      case 'delete':
        return await handleDelete(supabase, body, json)

      case 'add_comment':
        return await handleAddComment(supabase, user.id, body, json)

      case 'delete_comment':
        return await handleDeleteComment(supabase, body, json)

      default:
        return json({ error: `Unknown action: ${action}` }, 400)
    }
  } catch (e) {
    console.error('idea-board error:', e)
    return json({ error: 'Internal server error' }, 500)
  }
})

// ── Handlers ──────────────────────────────────────────────────────────────────

type JsonFn = (body: unknown, status?: number) => Response
type Supabase = ReturnType<typeof createClient>

async function handleList(supabase: Supabase, json: JsonFn) {
  const { data: ideas, error } = await supabase
    .from('ideas')
    .select('*')
    .is('deleted_at', null)
    .order('is_pinned', { ascending: false })
    .order('created_at', { ascending: false })

  if (error) {
    console.error('idea-board list error:', error)
    return json({ error: 'Failed to fetch ideas' }, 500)
  }

  // Fetch all comments for these ideas
  const ideaIds = (ideas ?? []).map((i: any) => i.id)

  let comments: any[] = []
  if (ideaIds.length > 0) {
    const { data: c, error: cErr } = await supabase
      .from('idea_comments')
      .select('*')
      .in('idea_id', ideaIds)
      .order('created_at', { ascending: true })

    if (cErr) {
      console.error('idea-board comments error:', cErr)
    } else {
      comments = c ?? []
    }
  }

  // Group comments by idea_id
  const commentMap: Record<string, any[]> = {}
  for (const c of comments) {
    if (!commentMap[c.idea_id]) commentMap[c.idea_id] = []
    commentMap[c.idea_id].push(c)
  }

  const result = (ideas ?? []).map((idea: any) => ({
    ...idea,
    comments: commentMap[idea.id] ?? [],
  }))

  return json({ ideas: result })
}

async function handleCreate(
  supabase: Supabase,
  userId: string,
  body: any,
  json: JsonFn,
) {
  const title = (body.title ?? '').trim()
  if (!title || title.length > 300) {
    return json({ error: 'Title is required (max 300 chars)' }, 400)
  }

  const { data, error } = await supabase
    .from('ideas')
    .insert({
      created_by: userId,
      title,
      description: (body.description ?? '').trim() || null,
      feature_tag: (body.feature_tag ?? 'general').trim(),
      status: body.status ?? 'open',
      priority: body.priority ?? 'medium',
      is_pinned: body.is_pinned ?? false,
    })
    .select()
    .single()

  if (error) {
    console.error('idea-board create error:', error)
    return json({ error: 'Failed to create idea' }, 500)
  }

  return json({ idea: { ...data, comments: [] } }, 201)
}

async function handleUpdate(supabase: Supabase, body: any, json: JsonFn) {
  const { id, ...updates } = body
  if (!id) return json({ error: 'id is required' }, 400)

  // Only allow specific fields
  const allowed: Record<string, any> = {}
  for (const key of ['title', 'description', 'feature_tag', 'status', 'priority', 'is_pinned']) {
    if (updates[key] !== undefined) allowed[key] = updates[key]
  }

  if (Object.keys(allowed).length === 0) {
    return json({ error: 'No fields to update' }, 400)
  }

  const { data, error } = await supabase
    .from('ideas')
    .update(allowed)
    .eq('id', id)
    .is('deleted_at', null)
    .select()
    .single()

  if (error) {
    console.error('idea-board update error:', error)
    return json({ error: 'Failed to update idea' }, 500)
  }

  return json({ idea: data })
}

async function handleDelete(supabase: Supabase, body: any, json: JsonFn) {
  const { id } = body
  if (!id) return json({ error: 'id is required' }, 400)

  const { error } = await supabase
    .from('ideas')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', id)
    .is('deleted_at', null)

  if (error) {
    console.error('idea-board delete error:', error)
    return json({ error: 'Failed to delete idea' }, 500)
  }

  return json({ success: true })
}

async function handleAddComment(
  supabase: Supabase,
  userId: string,
  body: any,
  json: JsonFn,
) {
  const { idea_id, comment } = body
  if (!idea_id) return json({ error: 'idea_id is required' }, 400)

  const text = (comment ?? '').trim()
  if (!text) return json({ error: 'comment is required' }, 400)

  const { data, error } = await supabase
    .from('idea_comments')
    .insert({ idea_id, created_by: userId, body: text })
    .select()
    .single()

  if (error) {
    console.error('idea-board add_comment error:', error)
    return json({ error: 'Failed to add comment' }, 500)
  }

  return json({ comment: data }, 201)
}

async function handleDeleteComment(supabase: Supabase, body: any, json: JsonFn) {
  const { comment_id } = body
  if (!comment_id) return json({ error: 'comment_id is required' }, 400)

  const { error } = await supabase
    .from('idea_comments')
    .delete()
    .eq('id', comment_id)

  if (error) {
    console.error('idea-board delete_comment error:', error)
    return json({ error: 'Failed to delete comment' }, 500)
  }

  return json({ success: true })
}
