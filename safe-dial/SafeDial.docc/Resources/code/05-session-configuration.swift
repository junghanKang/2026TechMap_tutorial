private let session = ARSession()
private var handler: ((Reading) -> Void)?

func start(handler: @escaping (Reading) -> Void) {
    guard ARWorldTrackingConfiguration.isSupported else { return }
    self.handler = handler
    startPosition = nil

    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = []
    configuration.environmentTexturing = .none
    configuration.isLightEstimationEnabled = false

    session.delegate = self
    session.delegateQueue = .main
    session.run(
        configuration,
        options: [.resetTracking, .removeExistingAnchors]
    )
}

func recenter() {
    startPosition = nil
}

func stop() {
    session.pause()
    session.delegate = nil
    handler = nil
}
