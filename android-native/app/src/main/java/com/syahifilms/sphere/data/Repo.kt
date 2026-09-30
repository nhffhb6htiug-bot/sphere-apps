package com.syahifilms.sphere.data

import org.json.JSONArray
import org.json.JSONObject

/** Everything the app does with the backend. Same tables and rules as the website. */
object Repo {

    // ---------------- profiles ----------------
    suspend fun loadMe(): Profile? {
        val uid = Api.userId ?: return null
        var row = Api.selectOne("profiles?id=eq.$uid&select=*")
        // email sign-up: profile is created on first login from sign-up details
        val meta = Api.userMeta
        if ((row == null || row.str("role").isBlank()) && meta.str("role").isNotBlank()) {
            try {
                Api.upsert("profiles", JSONObject()
                    .put("id", uid).put("role", meta.str("role"))
                    .put("full_name", meta.str("full_name").ifBlank { Api.email.substringBefore("@") })
                    .put("email", Api.email).put("phone", meta.str("phone")), "id")
            } catch (e: Exception) { }
            row = Api.selectOne("profiles?id=eq.$uid&select=*")
        }
        return row?.let { Profile.from(it) }
    }

    /** Role + number not confirmed yet -> show the "choose role" screen. */
    fun needsOnboarding(p: Profile?): Boolean =
        p == null || p.role.isBlank() || (p.role != "admin" && cleanIndianPhone(p.phone) == null)

    suspend fun saveRoleAndPhone(role: String, name: String, phone: String) {
        val uid = Api.userId ?: throw ApiException(401, "Please log in again")
        Api.upsert("profiles", JSONObject()
            .put("id", uid).put("role", role.uppercase()).put("full_name", name)
            .put("email", Api.email).put("phone", phone), "id")
    }

    suspend fun saveEditorDetails(
        phone: String, categories: List<String>, languages: List<String>, skills: String, experience: Int?,
        price: String, portfolio: String, sample: String
    ) {
        val uid = Api.userId ?: return
        val f = JSONObject()
            .put("phone", phone)
            .put("categories", JSONArray(categories))
            .put("languages", JSONArray(languages))
            .put("skills", JSONArray(skills.split(",").map { it.trim() }.filter { it.isNotBlank() }))
            .put("experience_years", experience ?: JSONObject.NULL)
            .put("price_range", price)
            .put("portfolio_url", portfolio.ifBlank { null } ?: JSONObject.NULL)
            .put("sample_video_url", sample)
        Api.update("profiles?id=eq.$uid", f)
    }

    suspend fun becomeEditor() {
        val uid = Api.userId ?: return
        Api.update("profiles?id=eq.$uid", JSONObject().put("role", "EDITOR"))
    }

    private suspend fun withRatings(list: List<Profile>): List<Profile> {
        if (list.isEmpty()) return list
        val ids = list.joinToString(",") { it.id }
        val rows = Api.select("sp_ratings?editor_id=in.($ids)&select=editor_id,stars")
        val sum = HashMap<String, Double>(); val n = HashMap<String, Int>()
        for (i in 0 until rows.length()) {
            val r = rows.getJSONObject(i); val e = r.str("editor_id")
            sum[e] = (sum[e] ?: 0.0) + r.optDouble("stars", 0.0); n[e] = (n[e] ?: 0) + 1
        }
        list.forEach { p -> val c = n[p.id] ?: 0; p.reviews = c; p.rating = if (c > 0) Math.round((sum[p.id] ?: 0.0) / c * 10) / 10.0 else 0.0 }
        return list
    }

    suspend fun verifiedEditors(category: String? = null): List<Profile> {
        var q = "sp_public_profiles?select=*"
        if (!category.isNullOrBlank()) q += "&categories=cs.${Api.enc("{\"$category\"}")}"
        val me = Api.userId
        return withRatings(Api.select(q).mapObjects { Profile.from(it) }.filter { it.id != me })
    }

    /** Full profile if you are connected (job / bid / chat), otherwise the public editor details. */
    suspend fun profile(id: String): Profile? {
        val row = Api.selectOne("profiles?id=eq.$id&select=*") ?: Api.selectOne("sp_public_profiles?id=eq.$id&select=*")
        return row?.let { withRatings(listOf(Profile.from(it))).first() }
    }

    suspend fun profilesByIds(ids: Collection<String>): Map<String, Profile> {
        val u = ids.filter { it.isNotBlank() }.distinct()
        if (u.isEmpty()) return emptyMap()
        val full = Api.select("profiles?id=in.(${u.joinToString(",")})&select=*").mapObjects { Profile.from(it) }
        val missing = u.filter { id -> full.none { it.id == id } }
        val pub = if (missing.isEmpty()) emptyList()
            else Api.select("sp_public_profiles?id=in.(${missing.joinToString(",")})&select=*").mapObjects { Profile.from(it) }
        val list = withRatings(full + pub)
        return list.associateBy { it.id }
    }

    // ---------------- notifications ----------------
    suspend fun notify(userIds: List<String>, title: String, body: String) {
        val ids = userIds.filter { it.isNotBlank() }
        if (ids.isEmpty()) return
        val rows = JSONArray()
        ids.forEach { rows.put(JSONObject().put("user_id", it).put("title", title).put("body", body)) }
        try { Api.insertMany("sp_notifications", rows) } catch (e: Exception) { }
    }

    suspend fun notifications(): List<Notice> {
        val me = Api.userId ?: return emptyList()
        val list = Api.select("sp_notifications?user_id=eq.$me&order=created_at.desc&limit=50").mapObjects { Notice.from(it) }
        if (list.any { !it.read }) {
            try { Api.update("sp_notifications?user_id=eq.$me&is_read=eq.false", JSONObject().put("is_read", true)) } catch (e: Exception) { }
        }
        return list
    }

    suspend fun unreadCount(): Int {
        val me = Api.userId ?: return 0
        return Api.select("sp_notifications?user_id=eq.$me&is_read=eq.false&select=id&limit=99").length()
    }

    // ---------------- jobs ----------------
    suspend fun job(id: String): Job? = Api.selectOne("sp_jobs?id=eq.$id&select=*")?.let { Job.from(it) }

    /** All open work (every category), newest first. The app lets the editor filter it. */
    suspend fun openJobs(): List<Job> {
        val me = Api.userId ?: return emptyList()
        val q = "sp_jobs?status=eq.open&client_id=neq.$me" +
            "&or=(deadline.is.null,deadline.gte.${todayIST()})&order=created_at.desc&select=*"
        return Api.select(q).mapObjects { Job.from(it) }
    }

    suspend fun myClientJobs(): List<Job> {
        val me = Api.userId ?: return emptyList()
        return Api.select("sp_jobs?client_id=eq.$me&order=created_at.desc&select=*").mapObjects { Job.from(it) }
    }

    suspend fun myEditorJobs(): List<Job> {
        val me = Api.userId ?: return emptyList()
        return Api.select("sp_jobs?assigned_editor=eq.$me&order=created_at.desc&select=*").mapObjects { Job.from(it) }
    }

    suspend fun postJob(
        me: Profile, category: String, description: String, budget: Double,
        deadline: String?, filesLink: String, presetEditor: String?, language: String = ""
    ): String {
        val row = JSONObject()
            .put("client_id", me.id).put("category", category).put("description", description)
            .put("budget", budget).put("deadline", deadline ?: JSONObject.NULL)
            .put("files_link", filesLink.ifBlank { null } ?: JSONObject.NULL)
            .put("language", language.ifBlank { null } ?: JSONObject.NULL)
            .put("status", if (presetEditor != null) "negotiating" else "open")
            .put("assigned_editor", presetEditor ?: JSONObject.NULL)
        val created = Api.insert("sp_jobs", row)
        if (presetEditor != null) {
            notify(listOf(presetEditor), "You were hired directly!", "${me.name} hired you for a $category project. Propose your price.")
        } else {
            val eds = Api.select("sp_public_profiles?categories=cs.${Api.enc("{\"$category\"}")}&select=id")
            notify(eds.mapObjects { it.str("id") }, "New Job Posted", "$category job posted — Budget ${money(budget)}")
        }
        return created?.str("id") ?: ""
    }

    suspend fun placeBid(me: Profile, job: Job, amount: Double, message: String) {
        try {
            Api.insert("sp_applications", JSONObject()
                .put("job_id", job.id).put("editor_id", me.id)
                .put("message", message.ifBlank { "I would love to work on this project." })
                .put("bid_amount", amount))
        } catch (e: ApiException) {
            if (e.pgCode == "23505") throw ApiException(409, "You have already placed a bid on this job.")
            if (e.pgCode == "42501" || e.message?.contains("row-level security") == true) {
                throw ApiException(403, if (!me.verified && me.role != "admin")
                    "You have used your ${Config.FREE_BIDS} free bids (or this job is closed). Get the ✔ tick from the Sphere team to bid without limits."
                else "This job is no longer open.")
            }
            throw e
        }
        notify(listOf(job.clientId), "New Bid Received", "${me.name} bid ${money(amount)} on your ${job.category} job.")
    }

    /** How many bids this user has placed in total (for the 3 free bids rule). */
    suspend fun myBidCount(): Int {
        val me = Api.userId ?: return 0
        return Api.select("sp_applications?editor_id=eq.$me&select=id&limit=50").length()
    }

    suspend fun bids(jobId: String): List<Bid> =
        Api.select("sp_applications?job_id=eq.$jobId&order=created_at.asc&select=*").mapObjects { Bid.from(it) }

    suspend fun selectEditor(job: Job, editorId: String, bidAmount: Double?) {
        val f = JSONObject().put("assigned_editor", editorId).put("status", "negotiating")
        if (bidAmount != null && bidAmount > 0) f.put("proposed_amount", bidAmount).put("proposed_by", editorId)
        Api.update("sp_jobs?id=eq.${job.id}", f)
        try { Api.update("sp_applications?job_id=eq.${job.id}&editor_id=eq.$editorId", JSONObject().put("status", "selected")) } catch (e: Exception) { }
        notify(listOf(editorId), "You got selected!", "The client selected you for the project. Please confirm the final price.")
    }

    suspend fun proposeAmount(me: Profile, job: Job, amount: Double, iAmClient: Boolean) {
        Api.update("sp_jobs?id=eq.${job.id}", JSONObject().put("proposed_amount", amount).put("proposed_by", me.id))
        val other = if (iAmClient) job.assignedEditor else job.clientId
        notify(listOf(other), "New Amount Proposed", "${money(amount)} proposed for your ${job.category} project.")
    }

    suspend fun acceptAmount(job: Job) {
        val amt = job.proposedAmount ?: return
        Api.update("sp_jobs?id=eq.${job.id}", JSONObject()
            .put("locked_amount", amt).put("budget", amt).put("status", "payment-pending"))
        notify(listOf(job.clientId), "Amount Locked 🔒", "Final amount ${money(amt)} is locked. Please make the payment.")
        notify(listOf(job.assignedEditor), "Amount Locked 🔒", "Final amount ${money(amt)} is locked. Waiting for the client's payment.")
    }

    suspend fun deliver(job: Job, link: String) {
        Api.update("sp_jobs?id=eq.${job.id}", JSONObject().put("delivery_link", link).put("status", "delivered"))
        notify(listOf(job.clientId), "Video Delivered", "Your editor has delivered the final video.")
    }

    /** Approve + release payment happens on the server (same as website). Returns payout state. */
    suspend fun approve(job: Job): String = Api.function("release-payout", JSONObject().put("jobId", job.id)).str("payout")

    suspend fun extendDeadline(job: Job, date: String) {
        Api.update("sp_jobs?id=eq.${job.id}", JSONObject().put("deadline", date))
    }

    suspend fun rate(job: Job, stars: Int, review: String) {
        val me = Api.userId ?: return
        try {
            Api.insert("sp_ratings", JSONObject().put("job_id", job.id).put("editor_id", job.assignedEditor)
                .put("client_id", me).put("stars", stars).put("review", review.ifBlank { null } ?: JSONObject.NULL))
        } catch (e: ApiException) {
            if (e.pgCode == "23505") throw ApiException(409, "You have already reviewed this project.")
            throw e
        }
        Api.update("sp_jobs?id=eq.${job.id}", JSONObject().put("status", "closed"))
        notify(listOf(job.assignedEditor), "New Review ⭐", "A client rated you $stars★.")
    }

    suspend fun hasRated(jobId: String): Boolean = Api.select("sp_ratings?job_id=eq.$jobId&select=id").length() > 0

    // ---------------- chat ----------------
    data class Conversation(val otherId: String, val last: ChatMessage)

    suspend fun conversations(): List<Conversation> {
        val me = Api.userId ?: return emptyList()
        val msgs = Api.select("sp_messages?or=(sender_id.eq.$me,receiver_id.eq.$me)&order=created_at.desc&limit=300&select=*")
            .mapObjects { ChatMessage.from(it) }
        val seen = LinkedHashMap<String, ChatMessage>()
        msgs.forEach { m -> val other = if (m.senderId == me) m.receiverId else m.senderId; if (!seen.containsKey(other)) seen[other] = m }
        return seen.map { Conversation(it.key, it.value) }
    }

    suspend fun thread(otherId: String): List<ChatMessage> {
        val me = Api.userId ?: return emptyList()
        val q = "sp_messages?or=(and(sender_id.eq.$me,receiver_id.eq.$otherId),and(sender_id.eq.$otherId,receiver_id.eq.$me))" +
            "&order=created_at.asc&limit=500&select=*"
        return Api.select(q).mapObjects { ChatMessage.from(it) }
    }

    suspend fun sendMessage(me: Profile, otherId: String, text: String) {
        Api.insert("sp_messages", JSONObject().put("sender_id", me.id).put("receiver_id", otherId).put("text", text))
        notify(listOf(otherId), "New Message", "${me.name}: ${text.take(80)}")
    }

    // ---------------- saved editors ----------------
    suspend fun isSaved(editorId: String): Boolean {
        val me = Api.userId ?: return false
        return Api.select("sp_saved?user_id=eq.$me&editor_id=eq.$editorId&select=editor_id").length() > 0
    }

    suspend fun setSaved(editorId: String, saved: Boolean) {
        val me = Api.userId ?: return
        if (saved) {
            try { Api.insert("sp_saved", JSONObject().put("user_id", me).put("editor_id", editorId)) }
            catch (e: ApiException) { if (e.pgCode != "23505") throw e }
        } else Api.delete("sp_saved?user_id=eq.$me&editor_id=eq.$editorId")
    }

    // ---------------- reports ----------------
    suspend fun report(jobId: String?, reason: String, details: String) {
        val me = Api.userId ?: return
        Api.insert("sp_reports", JSONObject().put("job_id", jobId ?: JSONObject.NULL)
            .put("reporter_id", me).put("reason", reason).put("details", details))
    }
}
