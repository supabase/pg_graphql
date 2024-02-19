use serde::Serialize;

#[derive(Serialize, Clone)]
#[serde(untagged)]
pub enum Omit<T> {
    Omitted,
    Present(T),
}

impl<T> Omit<T> {
    pub fn is_omit(&self) -> bool {
        matches!(self, Self::Omitted)
    }
}
