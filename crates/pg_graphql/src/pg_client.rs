pub trait PgClient {
    fn quote_ident(&self, ident: &str) -> String;
    fn quote_literal(&self, ident: &str) -> String;
}
