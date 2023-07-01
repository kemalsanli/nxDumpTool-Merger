//
//  NxDumpToolMerger.swift
//  nxDumpTool Merger
//
//  Created by Kemal Sanli on 17.01.2023.
//

import Cocoa

class NxDumpToolMerger: NSViewController {

    @IBOutlet weak var gameCount: NSTextField!
    @IBOutlet weak var inputTextInput: NSTextField!
    @IBOutlet weak var outputTextInput: NSTextField!
    @IBOutlet weak var convertButton: NSButton!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    
    var gameFoldersPath = Array<URL>()
    var total = 0
    
    var outputFolderExist: Bool = false
    var outputPath: URL = URL(fileURLWithPath: "")
    var convertIndex: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    
    @IBAction func selectInputFolderButton(_ sender: Any) {
        let dialog = fileSelector(title: "Select input folder", canSelectFiles: false)
        
        if dialog.runModal() == .OK, let result = dialog.url {
            let path: String = result.path
            inputTextInput.stringValue = path
            gameFoldersPath = scanPathForGameFolders(path: result)
            if gameFoldersPath.isEmpty {
                gameFoldersPath = scanFiles(path: result)
            }
            counterActions()
        }
    }
    
    @IBAction func selectOutputFolderButton(_ sender: Any) {
        let dialog = fileSelector(title: "Select output folder", canSelectFiles: false)
        
        if dialog.runModal() == .OK, let result = dialog.url {
            let path: String = result.path
            outputTextInput.stringValue = path
            outputPath = result
            outputFolderExist = true
        }
    }
    
    @IBAction func convertButton(_ sender: Any) {
        convertButton.isEnabled = false
        convertLoop()
    }
    
    func convertLoop() {
        let directoryContents = try! FileManager.default.contentsOfDirectory(
            at: gameFoldersPath[convertIndex],
            includingPropertiesForKeys: nil
        )
        performMergeOperation(files: directoryContents, url: gameFoldersPath[convertIndex]) { [weak self] _ in
            guard let self else { return }
            self.total = self.total + 1
            
            if convertIndex == gameFoldersPath.count - 1 {
                convertIndex = 0
            } else {
                convertIndex = convertIndex + 1
                convertLoop()
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshCounter()
            }
        }
    }
    
    func getFolderName(path: URL) -> String {
        return path.lastPathComponent
    }
    
    func counterActions() {
        gameCount.stringValue = "This folder contains \(gameFoldersPath.count) games for merge."
        if gameFoldersPath.count > 0 {
            convertButton.isEnabled = true
        } else {
            convertButton.isEnabled = false
        }
    }
    
    func scanFiles(path:URL) -> Array<URL> {
        let directoryContents = directoryContents(url: path)
        
        if !directoryContents.filter({ ($0.pathExtension == "nsp" || $0.pathExtension == "xci" || $0.pathExtension != "") }).isEmpty {
            return Array<URL>()
        } else if !directoryContents.filter({ $0.lastPathComponent == "00"}).isEmpty {
            return [path]
        }
        return Array<URL>()
    }
    
    func scanPathForGameFolders(path: URL) -> Array<URL> {
        let directoryContents = directoryContents(url: path)
        
        let subDirs = directoryContents.filter{ $0.hasDirectoryPath }
        let subDirsWithGames = subDirs.filter { $0.lastPathComponent.contains(".nsp") || $0.lastPathComponent.contains(".xci") }
        
        let subDirsWithGameButNoNSP = subDirsWithGames.filter {
            let contents = self.directoryContents(url: $0)
            for content in contents {
                if content.pathExtension == "xci" || content.pathExtension == "nsp" {
                    return false
                }
            }
            return true
        }
        return subDirsWithGameButNoNSP
    }
    
    func directoryContents(url: URL) -> [URL] {
        let directoryContents = try! FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )
        return directoryContents
    }
    
    func performMergeOperation(files: Array<URL>, url: URL, completion: @escaping (String) -> Void) {
        DispatchQueue.global().async { [weak self] in
            guard let self else {return}
            var commandArray: Array<String> = []
            var createCommand = ""
            
            for perFile in files where perFile.pathExtension == "" {
                if !isFileExtensionIncorrect(url: perFile, fileTypes: "nsp", "xci") {
                    commandArray.append("\"\( prepareStringForShell(releatedString: perFile.relativeString) )\" ")
                }
            }
            
            commandArray.sort()
            for command in commandArray {
                createCommand = createCommand + command
            }
            
            let destinationPath = outputFolderExist ? outputPath : url
            print("cat \(createCommand)> \"\( prepareStringForShell(releatedString: destinationPath.absoluteString) + getFolderName(path: url))\" ")
            completion( try! safeShell("cat \(createCommand)> \"\( prepareStringForShell(releatedString: destinationPath.absoluteString) + getFolderName(path: url))\" "))
        }
    }
    
    func isFileExtensionIncorrect(url: URL, fileTypes: String...) -> Bool {
        var isContain = false
        for fileType in fileTypes {
            if url.pathExtension == fileType || url.relativeString.contains("DS_Store"){
                isContain = true
            }
        }
        return isContain
    }
    
    func prepareStringForShell(releatedString: String) -> String {
        return releatedString.removeDeeplink().replacingOccurrences(of: "%20", with: " ")
    }
    
    
    @discardableResult // Add to suppress warnings when you don't want/need a result
    func safeShell(_ command: String) throws -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh") //<--updated
        task.standardInput = nil
        
        DispatchQueue.global(qos: .background).async {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                refreshCounter()
            }
            try! task.run() //<--updated
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!
        
        return output
    }
    func refreshCounter() {
        if self.total != self.gameFoldersPath.count {
            progressBar.isHidden = false
            self.convertButton.isEnabled = false
            progressBar.doubleValue = calculateProgress()
            print("calc prgoress: \(calculateProgress())")
            self.gameCount.stringValue = "Merging \(self.total + 1) of \(self.gameFoldersPath.count) game."
        } else {
            self.total = 0
            self.gameCount.stringValue = "Finished!"
            self.convertButton.isEnabled = true
            progressBar.isHidden = true
        }
        
    }
    
    func calculateProgress() -> Double {
        let convertedFolderCount: Double = Double(gameFoldersPath.count)
        let convertedTotalCount: Double = Double(total + 1)
        return (convertedTotalCount / convertedFolderCount) * 100
    }
    
    func fileSelector(title: String, canSelectFiles: Bool, allowedTypes: Array<String>? = []) -> NSOpenPanel {
        let dialog = NSOpenPanel();

        dialog.title                   = title
        dialog.showsResizeIndicator    = true
        dialog.showsHiddenFiles        = false
        dialog.allowsMultipleSelection = false
        dialog.canChooseFiles = canSelectFiles
        dialog.canChooseDirectories = !canSelectFiles
        if canSelectFiles {
            dialog.allowedFileTypes = allowedTypes
        }
        
        return dialog
    }

}

extension String {
    func removeDeeplink() -> String {
        var stringWithoutDeeplink = ""
        var counter = 0
        for perLetter in self {
            if perLetter == "/" {
                counter = counter + 1
            }
            if counter > 2 {
                stringWithoutDeeplink.append(perLetter)
            }
        }
        return stringWithoutDeeplink
    }
}


