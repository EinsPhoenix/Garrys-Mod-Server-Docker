-- Force-download the Jihad Bomb meme sound to every connecting client
-- so they all hear the same warning audio in the 50m radius.
if SERVER then
    resource.AddSingleFile("sound/ttt_jihad/wth.mp3")
end
