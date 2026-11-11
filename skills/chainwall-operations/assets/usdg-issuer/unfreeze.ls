{
  $require($subjectPolicy == {{governancePolicyId}}),
  $require($subjectVault == {{vault}}),
  $require($subjectNativeValue == 0),
  $require($subjectArgCount == 2),
  $require($arg1 > 0),
  @contract({{org}}/usdg).unfreeze($arg0 :: address)
}
