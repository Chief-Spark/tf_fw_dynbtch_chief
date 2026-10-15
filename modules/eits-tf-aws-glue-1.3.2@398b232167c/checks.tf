check "description_warning" {
  assert {
    condition     = var.database_description != null
    error_message = "AWS Best Practice recommends providing a useful description."
  }
}
