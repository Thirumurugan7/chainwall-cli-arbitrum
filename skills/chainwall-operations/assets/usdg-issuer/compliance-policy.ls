{
  $require(($subjectPolicy == {{compliancePolicyId}})),
  {
    $require(($subjectVault == {{vaultWord}})),
    {
      $require(($address({{coinKey}}) == {{coinWord}})),
      {
        $require(($subjectNativeValue == 0)),
        {
          $require(($subjectId == {{freezeId}})),
          {
            $require(($subjectArgCount == 1)),
            1
          }
        }
      }
    }
  }
}
