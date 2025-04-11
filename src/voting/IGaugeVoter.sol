/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGauge {
    /// @param metadataURI URI for the metadata of the gauge
    struct Gauge {
        bool active;
        uint256 created; // timestamp or epoch
        string metadataURI;
        // more space for data as this is a struct in a mapping
    }
}

/*///////////////////////////////////////////////////////////////
                            Gauge Manager
//////////////////////////////////////////////////////////////*/

interface IGaugeManagerEvents {
    event GaugeCreated(address indexed gauge, address indexed creator, string metadataURI);
    event GaugeDeactivated(address indexed gauge);
    event GaugeActivated(address indexed gauge);
    event GaugeMetadataUpdated(address indexed gauge, string metadataURI);
}

interface IGaugeManagerErrors {
    error ZeroGauge();
    error GaugeActivationUnchanged();
    error GaugeExists();
}

interface IGaugeManager is IGaugeManagerEvents, IGaugeManagerErrors {
    function isActive(address gauge) external view returns (bool);

    function createGauge(address _gauge, string calldata _metadata) external returns (address);

    function deactivateGauge(address _gauge) external;

    function activateGauge(address _gauge) external;

    function updateGaugeMetadata(address _gauge, string calldata _metadata) external;
}
