# RELEASE NOTES

## v1.3.2 - 13th September 2025

 - Updated `eits-tf-aws-iam` pinned version to `1.9.1`

## v1.3.1 - 23rd April 2025

- Updated Cloudwatch Logs module to bugfix version 2.5.1

## v1.3.0 - 7th April 2025

- Renamed `warnings.tf` to `checks.tf`
- Converted warnings to check blocks
- Updated IAM module dependency to 1.7.1
- Updated Cloudwatch Logs dependency version to 2.5.0
- Changed to use `ce-common` module instead of `vars`
- Updated module dependecies used in tests (IAM, KMS and S3)
- Removed `tlkamp/validation` provider

## v1.2.1 - 31th March 2025

- Updated depended IAM module version 1.5.0
- Updated review date

## v1.2.0 - 28th Feburary 2025

- New flag `configure_encryption_settings` to set up encryption for glue at the AWS account level.  Only needs to be done once per account to set encryption account-wide.  Assorted other variables are only needed when setting this flag to `true`.
- Added flag `create_cloudwatch_logs` for logging to Cloudwatch, it defaults to `true`, but can be disabled if not needed.  Utilizes EITS Cloudwatch logs module for log group creation.
- Added warning if `database_description` is left empty.

## v1.1.0 - 3rd September 2024

- Allow existing IAM role to be used with the addition of the following arguments:
  - `create_service_role`
  - `service_role_arn`
- Add new 'tests' directory to test an existing IAM role.

## v1.0.0 - 15th August 2024

- Initial release
