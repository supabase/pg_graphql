use crate::params::ParamBinder;

pub trait PgClient {
    type Args;

    fn quote_ident(&self, ident: &str) -> String;
    fn quote_literal(&self, ident: &str) -> String;
    fn execute_query<P: ParamBinder<Args = Self::Args>>(
        sql: &str,
        args: Self::Args,
    ) -> Result<serde_json::Value, String>;
}
