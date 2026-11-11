{
  $require($subjectPolicy == {{governancePolicyId}}),
  $require($subjectVault == {{vault}}),
  $require($subjectNativeValue == 0),
  $require($subjectArgCount == 3),
  $require($arg2 > 0),
  $require(@contract({{org}}/usdg).balanceOf($arg0 :: address) == $arg1),
  @contract({{org}}/usdg).wipeFrozenAddress($arg0 :: address)
}
