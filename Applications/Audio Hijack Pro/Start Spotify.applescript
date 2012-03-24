property scriptsFolder : (path to library folder from user domain as string) & "Scripts:"
property commonlib : load script alias (scriptsFolder & "Global.scpt")
property spotifylib : load script alias (scriptsFolder & "Applications:Audio Hijack Pro:Spotify.scpt")

try
	tell application "Audio Hijack Pro"
		activate
		set theSession to first session whose name is "Spotify" --By name		
		stop recording theSession
	end tell
on error
	display dialog "Start Spotify: Could not connect to Audio Hijack Pro, stopping script"
	return
end try

tell application "Finder" to open scriptsFolder & "Applications:Audio Hijack Pro:Run Spotify.app"
