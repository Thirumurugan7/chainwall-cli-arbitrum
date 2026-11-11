{
  $require(($subjectPolicy == {{redemptionPolicyId}})),
  {
    $require(($subjectVault == {{vaultWord}})),
    {
      $require(($address({{coinKey}}) == {{coinWord}})),
      {
        $require(($subjectNativeValue == 0)),
        {
          $require(($subjectId == {{burnId}})),
          {
            $require(($subjectArgCount == 1)),
            1
          }
        }
      }
    }
  }
}
