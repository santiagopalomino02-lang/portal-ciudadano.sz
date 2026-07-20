/* Configuración pública de Supabase. La publishable key puede estar en una app web;
   las reglas RLS del proyecto protegen los datos. Nunca incluyas una secret/service key aquí. */
window.SanzaSupabase = {
  url: 'https://fowqhnkdzfwdnhrfgdrb.supabase.co',
  publishableKey: 'sb_publishable_91lPQ8b2Eq8iNmkqSmULHQ__p47iVKR',
  enabled: true
};

/* El CUI se conserva como la credencial visible. Supabase Auth requiere un email,
   por lo que se genera un identificador técnico que nunca se muestra al ciudadano. */
function cuiToAuthEmail(cui) {
  return `${String(cui).trim().toLowerCase().replace(/[^a-z0-9-]/g, '')}@cui.portal-sanza.local`;
}

window.sanzaAuth = {
  client: null,
  init() {
    if (!window.SanzaSupabase.enabled || !window.supabase) return null;
    this.client = window.supabase.createClient(window.SanzaSupabase.url, window.SanzaSupabase.publishableKey);
    return this.client;
  },
  async loginWithCui(cui, password) {
    const client = this.client || this.init();
    if (!client) return null;
    const { data, error } = await client.auth.signInWithPassword({ email: cuiToAuthEmail(cui), password });
    if (error) throw new Error('CUI o contraseña incorrectos.');
    return data;
  },
  async logout() {
    if (this.client) await this.client.auth.signOut();
  },
  async getCurrentProfile() {
    const client = this.client || this.init();
    if (!client) return null;
    const { data: { user } } = await client.auth.getUser();
    if (!user) return null;
    const { data, error } = await client.from('profiles').select('*').eq('id', user.id).single();
    if (error) throw new Error('No fue posible cargar el perfil de la cuenta.');
    return data;
  }
};
