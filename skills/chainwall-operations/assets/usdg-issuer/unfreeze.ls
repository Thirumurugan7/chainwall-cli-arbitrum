{
  $require($subjectPolicy == {{compliancePolicyId}}),
  $require($subjectVault == {{vault}}),
  $require($subjectNativeValue == 0),
  $require($subjectArgCount == 1),
  @contract({{org}}/usdg).unfreeze($arg0 :: address)
}
