// SPDX License Identifier: AGPL-3.0 or later

pragma solidity ^0.8.17;

interface IMigrateableFrom {
    function migrator() external view returns (address);
    function enableMigration(address _migrator) external;
    function migrateFrom(uint256 _tokenId) external returns (uint256 newTokenId);
}

interface IMigrateableTo {
    function migrateTo(uint256 _value, address _for) external returns (uint256 newTokenId);
}

interface IMigrateableEventsAndErrors {
    /// @notice Emitted when the migrator is added, activating the migration
    event MigrationEnabled(address migrator);

    /// @notice Emitted when the user migrates to the new destination contract
    /// @param owner The owner of the veNFT at the time of the migration
    /// @param oldTokenId TokenId burned in the old staking contract
    /// @param newTokenId TokenId minted in the new staking contract
    /// @param amount The locked amount migrated between contracts
    event Migrated(
        address indexed owner,
        uint256 indexed oldTokenId,
        uint256 indexed newTokenId,
        uint256 amount
    );
    error MigrationAlreadySet();
    error MigrationNotActive();
    error MigrationActive();
}

interface IMigrateable is IMigrateableFrom, IMigrateableTo, IMigrateableEventsAndErrors {}
