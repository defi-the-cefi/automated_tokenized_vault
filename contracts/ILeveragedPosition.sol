

interface ILeveragedPosition {

  function deposit() external payable;

  // verify owner address with this
  function owner() external view returns(address);
  
  // get the address of the AAVE v3 lending pool
  function getLendingPool() external view returns(address);

}