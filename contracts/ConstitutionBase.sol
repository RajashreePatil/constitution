//  base contract for the urbit constitution
//  encapsulates dependencies all constitutions need.

pragma solidity 0.4.24;

import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';

import './ReadsShips.sol';
import './Polls.sol';

import './interfaces/ENS.sol';
import './interfaces/ResolverInterface.sol';

//  ConstitutionBase: upgradable constitution
//
//    This contract implements the upgrade logic for the Constitution.
//    Newer versions of the Constitution are expected to provide at least
//    the onUpgrade() function. If they don't, upgrading to them will fail.
//
//    Note that even though this contract doesn't specify any required
//    interface members aside from upgrade() and onUpgrade(), contracts
//    and clients may still rely on the presence of certain functions
//    provided by the Constitution proper. Keep this in mind when writing
//    updated versions of it.
//
contract ConstitutionBase is Ownable, ReadsShips
{
  event Upgraded(address to);

  //  polls: senate voting contract
  //
  Polls public polls;

  //  ens: ENS registry where ownership of the urbit domain is registered
  //
  ENS public ens;

  //  previousConstitution: address of the previous constitution this
  //                        instance expects to upgrade from, stored and
  //                        checked for to prevent unexpected upgrade paths
  //
  address public previousConstitution;

  //  baseNode: namehash of the urbit ens node
  //  subLabel: hash of the constitution's subdomain (without base domain)
  //  subNode:  namehash of the constitution's subnode
  //
  bytes32 public baseNode;
  bytes32 public subLabel;
  bytes32 public subNode;

  constructor(address _previous,
              Ships _ships,
              Polls _polls,
              ENS _ensRegistry,
              string _baseEns,
              string _subEns)
    ReadsShips(_ships)
    internal
  {
    previousConstitution = _previous;
    polls = _polls;
    ens = _ensRegistry;
    subLabel = keccak256(abi.encodePacked(_subEns));
    baseNode = keccak256(abi.encodePacked(
                 keccak256(abi.encodePacked( bytes32(0), keccak256('eth') )),
                 keccak256(abi.encodePacked( _baseEns )) ));
    subNode = keccak256(abi.encodePacked( baseNode, subLabel ));
  }

  //  onUpgrade(): called by previous constitution when upgrading
  //
  //    in future constitutions, this might perform more logic than
  //    just simple checks and verifications.
  //    when overriding this, make sure to call the original as well.
  //
  function onUpgrade()
    external
  {
    //  make sure this is the expected upgrade path,
    //  and that we have gotten the ownership we require
    //
    require( msg.sender == previousConstitution &&
             this == ships.owner() &&
             this == polls.owner() &&
             this == ens.owner(baseNode) &&
             this == ens.owner(subNode) );
  }

  //  upgrade(): transfer ownership of the constitution data to the new
  //             constitution contract, notify it, then self-destruct.
  //
  //    Note: any eth that have somehow ended up in the contract are also
  //          sent to the new constitution.
  //
  function upgrade(ConstitutionBase _new)
    internal
  {
    //  transfer ownership of the data contracts
    //
    ships.transferOwnership(_new);
    polls.transferOwnership(_new);

    //  make the ens resolver point to the new address, then transfer
    //  ownership of the urbit & constitution nodes to the new constitution.
    //
    //    Note: we're assuming we only register a resolver for the base node
    //          and don't have one registered for subnodes.
    //
    ResolverInterface resolver = ResolverInterface(ens.resolver(baseNode));
    resolver.setAddr(subNode, _new);
    ens.setSubnodeOwner(baseNode, subLabel, _new);
    ens.setOwner(baseNode, _new);

    //  trigger upgrade logic on the target contract
    //
    _new.onUpgrade();

    //  emit event and destroy this contract
    //
    emit Upgraded(_new);
    selfdestruct(_new);
  }
}
