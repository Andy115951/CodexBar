defineProvider({
  id: "chatbox",
  name: "Chatbox AI",
  endpoints: ["https://api.chatboxai.app"],
  auth: { type: "bearer", secret: "CHATBOX_LICENSE_KEY" },
  settings: [
    { key: "CHATBOX_LICENSE_KEY", title: "License key", type: "secure" },
    { key: "CHATBOX_AUTH_SOURCE", title: "Credential source", type: "plain" },
  ],
  capabilities: ["http-status"],
  async fetchUsage(ctx) {
    const url = "https://api.chatboxai.app/api/license/detail/all_status";
    const read = () => ctx.http.get(url);
    let response = await read();
    const record = (value: unknown): Record<string, unknown> | undefined =>
      value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : undefined;
    const decode = (body: string): Record<string, unknown> | undefined => {
      try {
        return record(JSON.parse(body));
      } catch (error) {
        void error;
        return undefined;
      }
    };
    // A read can apply the server's due plan downgrade. One further read obtains the new plan.
    if (response.status === 409 && record(decode(response.bodyText)?.error)?.code === "license_downgraded") {
      response = await read();
    }
    const message = `Chatbox AI returned HTTP ${response.status}.`;
    if (response.status === 401) {
      throw ctx.fail.authenticationExpired(
        "Chatbox AI rejected the license key. Refresh Chatbox or update the override.",
      );
    }
    if (response.status === 403) throw ctx.fail.permissionDenied(message);
    if (response.status === 429) {
      const delay = Number(response.headers["retry-after"] ?? 1);
      throw ctx.fail.rateLimited(message, {
        retryAfterSeconds: Number.isFinite(delay) && delay >= 0 ? Math.min(delay, 10) : 1,
      });
    }
    if (response.status >= 500) throw ctx.fail.providerUnavailable(message);
    if (response.status === 409) {
      throw ctx.fail.apiFailure("Chatbox AI plan changed. Refresh to read the current plan.");
    }
    if (response.status !== 200) throw ctx.fail.apiFailure(message);
    const fail = (): never => {
      throw ctx.fail.parseFailure("Chatbox AI returned an unrecognized license response.");
    };
    const root = decode(response.bodyText);
    const data = record(root?.data);
    if (!data || root?.error) return fail();
    const now = ctx.date.now().getTime();
    const text = (value: unknown): string | undefined =>
      typeof value === "string"
        ? Array.from(value, (character) => {
            const code = character.charCodeAt(0);
            return code < 32 || code === 127 ? " " : character;
          })
            .join("")
            .trim()
            .slice(0, 100) || undefined
        : undefined;
    const counter = (value: unknown): number | undefined => {
      if (value === undefined || value === null) return undefined;
      return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : fail();
    };
    const date = (value: unknown): Date | undefined => {
      if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T/.test(value)) return undefined;
      const parsed = new Date(value);
      return Number.isFinite(parsed.getTime()) && parsed.getUTCFullYear() >= 1970 ? parsed : undefined;
    };
    type Pool = { used: number; limit: number };
    const pool = (object: Record<string, unknown>, usedKey: string, limitKey: string): Pool | undefined => {
      const used = counter(object[usedKey]);
      const limit = counter(object[limitKey]);
      return used !== undefined && limit !== undefined ? { used, limit } : undefined;
    };
    const rows: CodexBarDetailRow[] = [];
    const addPool = (label: string, value: Pool | undefined) => {
      if (!value || (value.used === 0 && value.limit === 0)) return;
      const remaining = Math.max(value.limit - value.used, 0);
      rows.push({
        label,
        value: `${ctx.format.number(remaining)} / ${ctx.format.number(value.limit)}`,
        usageValue: value.used,
      });
    };
    const details = data.unified_token_usage_details;
    let plan: Pool | undefined;
    let detailRewards: Pool | undefined;
    if (details !== undefined && details !== null) {
      if (!Array.isArray(details) || details.length > 100) return fail();
      for (const entry of details) {
        const item = record(entry);
        if (!item || typeof item.type !== "string") return fail();
        const value = pool(item, "token_usage", "token_limit");
        if (item.type === "plan") {
          if (plan) return fail();
          plan = value;
        } else if (value) {
          const expires = date(item.expires_at);
          if (expires && expires.getTime() <= now) continue;
          detailRewards = {
            used: (detailRewards?.used ?? 0) + value.used,
            limit: (detailRewards?.limit ?? 0) + value.limit,
          };
          if (!Number.isSafeInteger(detailRewards.used) || !Number.isSafeInteger(detailRewards.limit)) return fail();
        }
      }
    }
    const total = pool(data, "unified_token_usage", "unified_token_limit");
    const rewardRecord = record(data.aggregated_reward_details);
    if (data.aggregated_reward_details != null && !rewardRecord) return fail();
    const rewards = rewardRecord ? pool(rewardRecord, "token_usage", "token_limit") : detailRewards;
    const expansion = pool(data, "expansion_pack_usage", "expansion_pack_limit");
    const images = pool(data, "image_used_count", "image_total_quota");
    if (!plan && !total && !rewards && !expansion && !images) return fail();
    addPool("Plan compute points", plan);
    if (!plan) addPool("Combined compute points", total);
    addPool("Reward compute points", rewards);
    addPool("Expansion pack", expansion);
    addPool("Images", images);
    const name = text(data.name);
    const status = text(data.status);
    const expires = date(data.token_expire_time) ?? date(data.expires_at);
    const next = date(data.token_next_refresh_time);
    const usablePlan =
      ["active", "inactive", "refunding"].includes(status ?? "") &&
      (data.plan === "free" || !expires || expires.getTime() > now);
    // Trial has no positive plan pool. Rewards and image totals do not share the plan's reset schedule.
    const reset =
      usablePlan &&
      plan &&
      plan.limit > 0 &&
      next &&
      next.getTime() > now &&
      (!expires || next.getTime() < expires.getTime())
        ? next
        : undefined;
    if (status) rows.push({ label: "License status", value: status });
    const source = ctx.settings.get("CHATBOX_AUTH_SOURCE");
    rows.push({
      label: "Credential source",
      value:
        source === "app-login"
          ? "Chatbox app account"
          : source === "app-license"
            ? "Chatbox app license"
            : "Manual key",
    });
    return {
      primary:
        usablePlan && plan && plan.limit > 0
          ? {
              usedPercent: ctx.pct(plan.used, plan.limit),
              resetsAt: reset,
              windowMinutes: data.plan === "free" ? 1440 : undefined,
            }
          : undefined,
      secondary:
        expansion && expansion.limit > 0 ? { usedPercent: ctx.pct(expansion.used, expansion.limit) } : undefined,
      identity: name ? { loginMethod: name } : undefined,
      details: [{ title: "Remaining quota", rows }],
      subscriptionExpiresAt: expires,
      dataConfidence: "exact",
    };
  },
});
