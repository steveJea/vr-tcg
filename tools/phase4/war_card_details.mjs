// Explicit public combat metadata only; NEVER disclose owned UIDs or arbitrary snapshot keys.
export const detailProjection="'snapshot', jsonb_build_object('id',c->'id','level',c->'level','ex',c->'ex','exb',c->'exb','boost',c->'boost','skillLv',c->'skillLv','gear',c->'gear','sigil',c->'sigil','scale',c->'scale'), ";
