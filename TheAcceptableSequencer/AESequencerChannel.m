//
//  AESequencer.m
//  TheAcceptableSequencer
//
//  Created by Alejandro Santander on 8/1/15.
//  Copyright (c) 2015 Palebluedot. All rights reserved.
//

#import "AESequencerChannel.h"
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

@implementation AESequencerChannel {
    AEAudioController *_audioController;
    MusicPlayer _player;
    MusicSequence _sequence;
    BOOL _isPlaying;
    float _resolution;
}

// ---------------------------------------------------------------------------------------------------------
#pragma mark - INIT
// ---------------------------------------------------------------------------------------------------------

- (instancetype)initWithAudioController:(AEAudioController*)audioController andPatternResolution:(float)resolution {
    
    _audioController = audioController;
    _isPlaying = NO;
    _resolution = resolution;
    
    // Init as an AUSampler audio unit channel.
    AudioComponentDescription component = AEAudioComponentDescriptionMake(kAudioUnitManufacturer_Apple, kAudioUnitType_MusicDevice, kAudioUnitSubType_Sampler);
    NSError *error = NULL;
    self = [super initWithComponentDescription:component audioController:audioController error:&error];
    if(error) NSLog(@"  AUSampler creation error: %@", error);
    else NSLog(@"  AUSampler started ok.");
    
    // Create a MusicPlayer to control playback.
    NewMusicPlayer(&_player);
    
    // Init data.
    _pattern = [NSMutableDictionary dictionary];
    
    return self;
}

// ---------------------------------------------------------------------------------------------------------
#pragma mark - LOAD MIDI FILES
// ---------------------------------------------------------------------------------------------------------

- (void)loadMidiFile:(NSURL*)fileURL {
    
    // Load and parse the midi data.
    MusicSequence sequence;
    NewMusicSequence(&sequence);
    MusicSequenceFileLoad(sequence, (__bridge CFURLRef)fileURL, 0, 0);
    [self loadSequence:sequence];
}

- (void)loadSequence:(MusicSequence)sequence {
    
    _sequence = sequence;
    
    // Tell the sequence that it will be played by the sampler.
    CheckError(MusicSequenceSetAUGraph(_sequence, _audioController.audioGraph), "Error connecting sampler.");
//    CAShow(_audioController.audioGraph);
    
    // Load the sequence on the player.
    MusicPlayerSetSequence(_player, _sequence);
    MusicPlayerPreroll(_player);
    [self toggleLooping:YES onSequence:sequence];
    
    // Build pattern.
    [self musicSequenceToPattern];
}

// ---------------------------------------------------------------------------------------------------------
#pragma mark - PATTERN
// ---------------------------------------------------------------------------------------------------------

- (void)toggleNoteOnAtIndexPath:(NSIndexPath*)indexPath on:(BOOL)on {
    
    // Update data grid.
    _pattern[indexPath] = on ? @1 : @0;
    
    // Update sequence.
    [self dataToMusicTrack];
}

- (void)dataToMusicTrack {
    
    // Get track 1. (0 is tempo).
    int trackIndex = 1;
    MusicTrack track;
    CheckError(MusicSequenceGetIndTrack(_sequence, trackIndex, &track), "Error getting track.");
    
    // Clear MusicTrack.
    MusicTimeStamp startTime = 0;
    MusicTimeStamp endTime = _patternLengthInBeats;
    CheckError(MusicTrackClear(track, startTime, endTime), "Error clearing music track.");
    
    // Sweep cells.
    MusicTimeStamp time = 0;
    MusicTimeStamp duration = 1.0;
    int sectionCount = 10;
    int rowCount = _patternLengthInBeats / _resolution;
    for(int rowIndex = startTime; rowIndex < rowCount; rowIndex++) {
        for(int sectionIndex = 0; sectionIndex < sectionCount; sectionIndex++) {
            
            // Id index path.
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:rowIndex inSection:sectionIndex];
            
            // ON?
            if(_pattern[indexPath] && [_pattern[indexPath] isEqualToNumber:@1]) {
                MIDINoteMessage note;
                note.note = 36 + sectionIndex;
                note.channel = 1;
                note.velocity = 100.00;
                note.duration = 1.0;
                time = rowIndex * _resolution - duration;
                CheckError(MusicTrackNewMIDINoteEvent(track, time, &note), "Error adding note.");
            }
        }
    }
}

- (void)musicSequenceToPattern {
    
    NSLog(@"musicSequenceToPattern()");
    
    // Get track 1. (0 is tempo).
    int trackIndex = 1;
    MusicTrack track;
    CheckError(MusicSequenceGetIndTrack(_sequence, trackIndex, &track), "Error getting track.");
    
    // Get track info.
    MusicTimeStamp trackLength = 0;
    UInt32 trackLenLength_size = sizeof(trackLength);
    CheckError(MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &trackLength, &trackLenLength_size), "Error getting track info");
    _patternLengthInBeats = trackLength;
    
    // Sweep events and convert notes to the grid.
    MusicEventIterator iterator = NULL;
    NewMusicEventIterator(track, &iterator);
    MusicTimeStamp timestamp = 0; // all extracted time values are in beats (black notes)
    MusicEventType eventType = 0;
    const void *eventData = NULL;
    UInt32 eventDataSize;
    Boolean hasNext = YES;
    int j = 0;
    while(hasNext) {
        
        // Next iteration.
        MusicEventIteratorHasNextEvent(iterator, &hasNext);
        if(j > 5000) { hasNext = false; } // bail out
        
        // Get event info.
        MusicEventIteratorGetEventInfo(iterator, &timestamp, &eventType, &eventData, &eventDataSize);
        
        // NOTE EVENT
        if(eventType == kMusicEventType_MIDINoteMessage) {
            
            // Cast message.
            MIDINoteMessage *message = (MIDINoteMessage*)eventData;
            
            // Log note.         
            UInt8 note = message->note;
            NSLog(@"note: %d", note);
            int noteSection = note - 36;
            int noteRow = timestamp * (1/_resolution);
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:noteRow inSection:noteSection];
            _pattern[indexPath] = [NSNumber numberWithBool:YES];
        }
        
        // Iterate.
        MusicEventIteratorNextEvent(iterator);
        j++;
    }
}

- (BOOL)isNoteOnAtIndexPath:(NSIndexPath*)indexPath {
    BOOL isOn = NO;
    if(_pattern[indexPath] && [_pattern[indexPath] isEqualToNumber:@1]) {
        isOn = YES;
    }
    return isOn;
}

// ---------------------------------------------------------------------------------------------------------
#pragma mark - LOAD PRESETS
// ---------------------------------------------------------------------------------------------------------

- (void)loadPreset:(NSURL*)fileURL {
    
    // Prepare preset object.
    AUSamplerInstrumentData auPreset = {0};
    auPreset.fileURL = (__bridge CFURLRef)(fileURL);
//    auPreset.bankMSB = kAUSampler_DefaultMelodicBankMSB;
//    auPreset.bankLSB = kAUSampler_DefaultBankLSB;
    auPreset.instrumentType = kInstrumentType_AUPreset;
//    auPreset.presetID = 0;
    
    // Load preset.
    CheckError(AudioUnitSetProperty(self.audioUnit,
                                    kAUSamplerProperty_LoadInstrument,
                                    kAudioUnitScope_Global,
                                    0,
                                    &auPreset,
                                    sizeof(auPreset)), "Error loading preset.");
}

// ---------------------------------------------------------------------------------------------------------
#pragma mark - PLAYBACK
// ---------------------------------------------------------------------------------------------------------

- (void)play {
    if(_isPlaying) return;
    CheckError(MusicPlayerStart(_player), "Error starting music player.");
    _isPlaying = YES;
}

- (void)stop {
    if(!_isPlaying) return;
    MusicPlayerStop(_player);
    _isPlaying = NO;
}

// ---------------------------------------------------------------------------------------------------------
#pragma mark - UTILS
// ---------------------------------------------------------------------------------------------------------

- (void)toggleLooping:(BOOL)loop onSequence:(MusicSequence)sequence {
    
    // Get number of tracks.
    UInt32 numberOfTracks;
    MusicSequenceGetTrackCount(sequence, &numberOfTracks);
    
    // Sweep tracks.
    MusicTrack track;
    MusicTimeStamp trackLength = 0;
    UInt32 trackLenLength_size = sizeof(trackLength);
    for(UInt32 i = 0; i < numberOfTracks; i++) {
        
        // Get track.
        MusicSequenceGetIndTrack(sequence, i, &track);
        
        // Get track info.
        MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &trackLength, &trackLenLength_size);
        
        // Set new loop info.
        MusicTrackLoopInfo loopInfo = { trackLength, 0 }; // loopDuration:MusicTimeStamp, numberOfLoops:SInt32
        MusicTrackSetProperty(track, kSequenceTrackProperty_LoopInfo, &loopInfo, sizeof(loopInfo));
    }
}

static void CheckError(OSStatus error, const char *operation) {
    if (error == noErr) return;
    
    char errorString[20];
    // see if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else
        // no, format it as an integer
        sprintf(errorString, "%d", (int)error);
    
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    
    exit(1);
}

@end
























