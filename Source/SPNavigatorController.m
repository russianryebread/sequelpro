//
//  $Id$
//
//  SPNavigatorController.m
//  sequel-pro
//
//  Created by Hans-J. Bibiko on March 17, 2010.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//
//  More info at <http://code.google.com/p/sequel-pro/>

#import "SPNavigatorController.h"
#import "RegexKitLite.h"
#import "SPNavigatorOutlineView.h"
#import "SPConstants.h"
#import "ImageAndTextCell.h"
#import "TableDocument.h"
#import "TablesList.h"
#import "SPArrayAdditions.h"
#import "SPLogger.h"
#import "SPTooltip.h"

static SPNavigatorController *sharedNavigatorController = nil;

#define DragFromNavigatorPboardType  @"SPDragFromNavigatorPboardType"

@implementation SPNavigatorController

/*
 * Returns the shared query console.
 */
+ (SPNavigatorController *)sharedNavigatorController
{
	@synchronized(self) {
		if (sharedNavigatorController == nil) {
			sharedNavigatorController = [[super allocWithZone:NULL] init];
		}
	}

	return sharedNavigatorController;
}

+ (id)allocWithZone:(NSZone *)zone
{    
	@synchronized(self) {
		return [[self sharedNavigatorController] retain];
	}
}

- (id)init
{
	if((self = [super initWithWindowNibName:@"Navigator"])) {

		schemaDataFiltered  = [[NSMutableDictionary alloc] init];
		allSchemaKeys       = [[NSMutableDictionary alloc] init];
		schemaData          = [[NSMutableDictionary alloc] init];
		expandStatus1       = [[NSMutableDictionary alloc] init];
		expandStatus2       = [[NSMutableDictionary alloc] init];
		infoArray           = [[NSMutableArray alloc] init];
		selectedKey1        = @"";
		selectedKey2        = @"";
		ignoreUpdate        = NO;
		isFiltered          = NO;
		[syncButton setState:NSOffState];
		
	}

	return self;

}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if(schemaDataFiltered) [schemaDataFiltered release];
	if(allSchemaKeys) [allSchemaKeys release];
	if(schemaData) [schemaData release];
	if(infoArray)  [infoArray release];
	if(expandStatus1) [expandStatus1 release];
	if(expandStatus2) [expandStatus2 release];
}
/*
 * The following base protocol methods are implemented to ensure the singleton status of this class.
 */

- (id)copyWithZone:(NSZone *)zone { return self; }

- (id)retain { return self; }

- (NSUInteger)retainCount { return NSUIntegerMax; }

- (id)autorelease { return self; }

- (void)release { }

/**
 * Set the window's auto save name and initialise display
 */
- (void)awakeFromNib
{
	prefs = [NSUserDefaults standardUserDefaults];

	[self setWindowFrameAutosaveName:@"SPNavigator"];
	[outlineSchema1 registerForDraggedTypes:[NSArray arrayWithObjects:DragFromNavigatorPboardType, NSStringPboardType, nil]];
	[outlineSchema1 setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];
	[outlineSchema1 setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
	[outlineSchema2 registerForDraggedTypes:[NSArray arrayWithObjects:DragFromNavigatorPboardType, NSStringPboardType, nil]];
	[outlineSchema2 setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];
	[outlineSchema2 setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateNavigator:)
												 name:@"SPDBStructureWasUpdated" object:nil];

}

- (NSString *)windowFrameAutosaveName
{
	return @"SPNavigator";
}

#pragma mark -

- (BOOL)syncMode
{
	if([[self window] isVisible])
		return ([syncButton state] == NSOffState || [outlineSchema2 numberOfSelectedRows] > 1) ? NO : YES;
	return NO;
}

- (void)restoreExpandStatus
{

	if(!schemaData) return;

	NSInteger i;
	for( i = 0; i < [outlineSchema1 numberOfRows]; i++ ) {
		id item = [outlineSchema1 itemAtRow:i];
		id parentObject = [outlineSchema1 parentForItem:item] ? [outlineSchema1 parentForItem:item] : schemaData;
		if(!parentObject) return;
		id parentKeys = [parentObject allKeysForObject:item];
		if(parentKeys && [parentKeys count] == 1)
			if( [expandStatus1 objectForKey:[parentKeys objectAtIndex:0]] )
				[outlineSchema1 expandItem:item];
	}
	if(!isFiltered) {
		for( i = 0; i < [outlineSchema2 numberOfRows]; i++ ) {
			id item = [outlineSchema2 itemAtRow:i];
			id parentObject = [outlineSchema2 parentForItem:item] ? [outlineSchema2 parentForItem:item] : schemaData;
			id parentKeys = [parentObject allKeysForObject:item];
			if(parentKeys && [parentKeys count] == 1)
				if( [expandStatus2 objectForKey:[parentKeys objectAtIndex:0]] )
					[outlineSchema2 expandItem:item];
		}
	}
}

- (void)saveSelectedItems
{
	selectedKey1 = @"";
	selectionViewPort1 = [outlineSchema1 visibleRect];
	if(schemaData) {
		id selection = nil;
		selection = [outlineSchema1 selectedItem];
		if(selection) {
			id parentObject = [outlineSchema1 parentForItem:selection] ? [outlineSchema1 parentForItem:selection] : schemaData;
			if(!parentObject) return;
			id parentKeys = [parentObject allKeysForObject:selection];
			if(parentKeys && [parentKeys count] == 1)
				selectedKey1 = [[parentKeys objectAtIndex:0] description];
		}
		
		if(isFiltered) return;

		selectedKey2 = @"";
		selectionViewPort2 = [outlineSchema2 visibleRect];

		selection = [outlineSchema2 selectedItem];
		if(selection) {
			id parentObject = [outlineSchema2 parentForItem:selection] ? [outlineSchema2 parentForItem:selection] : schemaData;
			if(!parentObject) return;
			id parentKeys = [parentObject allKeysForObject:selection];
			if(parentKeys && [parentKeys count] == 1)
				selectedKey2 = [[parentKeys objectAtIndex:0] description];
		}
	}

}

- (void)selectPath:(NSString*)schemaPath
{
	if(schemaPath && [schemaPath length]) {

		// Do not change the selection if a field of schemaPath's table is already selected
		[self saveSelectedItems];
		if([selectedKey2 length] && [selectedKey2 hasPrefix:[NSString stringWithFormat:@"%@%@", schemaPath, SPUniqueSchemaDelimiter]])
			return;

		id item = schemaData;
		NSArray *pathArray = [schemaPath componentsSeparatedByString:SPUniqueSchemaDelimiter];
		if(!pathArray || [pathArray count] == 0) return;
		NSMutableString *aKey = [NSMutableString string];
		[outlineSchema2 collapseItem:[item objectForKey:[pathArray objectAtIndex:0]] collapseChildren:YES];
		for(NSInteger i=0; i < [pathArray count]; i++) {
			[aKey appendString:[pathArray objectAtIndex:i]];
			if(![item objectForKey:aKey]) break;
			item = [item objectForKey:aKey];
			[outlineSchema2 expandItem:item];
			[aKey appendString:SPUniqueSchemaDelimiter];
		}
		if(item != nil) {
			NSInteger itemIndex = [outlineSchema2 rowForItem:item];
			if (itemIndex >= 0) {
				[outlineSchema2 selectRowIndexes:[NSIndexSet indexSetWithIndex:itemIndex] byExtendingSelection:NO];
				if([outlineSchema2 numberOfSelectedRows] != 1) return;
				[outlineSchema2 scrollRowToVisible:[outlineSchema2 selectedRow]];
				id item = [outlineSchema2 selectedItem];
				// Try to scroll the view that all children of schemaPath are visible if possible
				NSInteger cnt = 1;
				if([item isKindOfClass:[NSDictionary class]] || [item isKindOfClass:[NSArray class]])
					cnt = [item count]+1;
				NSRange r = [outlineSchema2 rowsInRect:[outlineSchema2 visibleRect]];
				NSInteger offset = (cnt > r.length) ? (r.length-2) : cnt;
				offset += [outlineSchema2 selectedRow];
				if(offset >= [outlineSchema2 numberOfRows])
					offset = [outlineSchema2 numberOfRows] - 1;
				[outlineSchema2 scrollRowToVisible:offset];
			}
		}
	}
}

- (void)restoreSelectedItems
{

	if(!schemaData) return;

	BOOL viewportWasValid1 = NO;
	BOOL viewportWasValid2 = NO;
	selectionViewPort1.size = [outlineSchema1 visibleRect].size;
	selectionViewPort2.size = [outlineSchema2 visibleRect].size;
	viewportWasValid1 = [outlineSchema1 scrollRectToVisible:selectionViewPort1];
	viewportWasValid2 = [outlineSchema2 scrollRectToVisible:selectionViewPort2];
	if(selectedKey1 && [selectedKey1 length]) {
		id item = schemaData;
		NSArray *pathArray = [selectedKey1 componentsSeparatedByString:SPUniqueSchemaDelimiter];
		NSMutableString *aKey = [NSMutableString string];
		for(NSInteger i=0; i < [pathArray count]; i++) {
			[aKey appendString:[pathArray objectAtIndex:i]];
			if(![item objectForKey:aKey]) break;
			item = [item objectForKey:aKey];
			[aKey appendString:SPUniqueSchemaDelimiter];
		}
		if(item != nil) {
			NSInteger itemIndex = [outlineSchema1 rowForItem:item];
			if (itemIndex >= 0) {
				[outlineSchema1 selectRowIndexes:[NSIndexSet indexSetWithIndex:itemIndex] byExtendingSelection:NO];
				if(!viewportWasValid1)
					[outlineSchema1 scrollRowToVisible:[outlineSchema1 selectedRow]];
			}
		}
	}
	if(!isFiltered && selectedKey2 && [selectedKey2 length]) {
		id item = schemaData;
		NSArray *pathArray = [selectedKey2 componentsSeparatedByString:SPUniqueSchemaDelimiter];
		NSMutableString *aKey = [NSMutableString string];
		for(NSInteger i=0; i < [pathArray count]; i++) {
			[aKey appendString:[pathArray objectAtIndex:i]];
			if(![item objectForKey:aKey]) break;
			item = [item objectForKey:aKey];
			[aKey appendString:SPUniqueSchemaDelimiter];
		}
		if(item != nil) {
			NSInteger itemIndex = [outlineSchema2 rowForItem:item];
			if (itemIndex >= 0) {
				[outlineSchema2 selectRowIndexes:[NSIndexSet indexSetWithIndex:itemIndex] byExtendingSelection:NO];
				if(!viewportWasValid2)
					[outlineSchema2 scrollRowToVisible:[outlineSchema2 selectedRow]];
			}
		}
	}
}

- (void)setIgnoreUpdate:(BOOL)flag
{
	ignoreUpdate = flag;
}

- (void)removeConnection:(NSString*)connectionID
{
	if(schemaData && [schemaData objectForKey:connectionID]) {
		
		NSInteger docCounter = 0;

		// Detect if more than one connection windows with the connectionID are open.
		// If so, don't remove it.
		if ([[[NSDocumentController sharedDocumentController] documents] count]) {
			for(id doc in [[NSDocumentController sharedDocumentController] documents]) {
				if(![[doc valueForKeyPath:@"mySQLConnection"] isConnected]) continue;
				if([[doc connectionID] isEqualToString:connectionID])
					docCounter++;
				if(docCounter > 1) break;
			}
		}

		if(docCounter > 1) return;
		
		[schemaDataFiltered removeObjectForKey:connectionID];
		[schemaData removeObjectForKey:connectionID];
		[allSchemaKeys removeObjectForKey:connectionID];
		[self saveSelectedItems];
		[outlineSchema1 reloadData];
		[outlineSchema2 reloadData];
		[self restoreSelectedItems];
		if(isFiltered)
			[self filterTree:self];
	}
}

- (void)selectInActiveDocumentItem:(id)item fromView:(id)outlineView
{
	if([outlineView levelForItem:item] == 0) return;
	
	id parentObject = [outlineView parentForItem:item] ? [outlineView parentForItem:item] : schemaData;
	if(!parentObject) return;
	id parentKeys = [parentObject allKeysForObject:item];
	if(parentKeys && [parentKeys count] == 1) {

		NSPoint pos = [NSEvent mouseLocation];
		pos.y -= 20;

		NSArray *pathArray = [[[parentKeys objectAtIndex:0] description] componentsSeparatedByString:SPUniqueSchemaDelimiter];
		if([pathArray count] > 1) {

			TableDocument *doc = [[NSDocumentController sharedDocumentController] currentDocument];
			if([doc isWorking]) {
				[SPTooltip showWithObject:NSLocalizedString(@"Active connection window is busy. Please wait and try again.", @"active connection window is busy. please wait and try again. tooltip") 
						atLocation:pos 
						ofType:@"text"];
				return;
			}
			if([[doc connectionID] isEqualToString:[pathArray objectAtIndex:0]]) {

				// Select the database and table
				[doc selectDatabase:[pathArray objectAtIndex:1] item:([pathArray count] > 2)?[pathArray objectAtIndex:2]:nil];

			} else {

				[SPTooltip showWithObject:NSLocalizedString(@"The connection of the active connection window is not identical.", @"the connection of the active connection window is not identical tooltip") 
						atLocation:pos 
						ofType:@"text"];

			}
		}
	}
}

- (void)updateNavigator:(NSNotification *)aNotification
{
	id object = [aNotification object];
	
	if([object isKindOfClass:[TableDocument class]])
		[self performSelectorOnMainThread:@selector(updateEntriesForConnection:) withObject:[object connectionID] waitUntilDone:YES];
	else
		[self performSelectorOnMainThread:@selector(updateEntriesForConnection:) withObject:nil waitUntilDone:YES];
}

- (void)updateEntriesForConnection:(NSString*)connectionID
{

	if(![[self window] isVisible]) return;
	NSLog(@"UPDATE NAVIGATOR called");
	if(ignoreUpdate) {
		ignoreUpdate = NO;
		return;
	}

	[self saveSelectedItems];

	[infoArray removeAllObjects];
	
	if ([[[NSDocumentController sharedDocumentController] documents] count]) {
		for(id doc in [[NSDocumentController sharedDocumentController] documents]) {

			id theConnection = [doc valueForKeyPath:@"mySQLConnection"];

			if(!theConnection || ![theConnection isConnected]) continue;

			NSString *connectionName = [doc connectionID];

			if(!connectionName || [connectionName isEqualToString:@"_"] || (connectionID && ![connectionName isEqualToString:connectionID]) ) continue;

			if(![schemaData objectForKey:connectionName]) {
				[schemaData setObject:[NSMutableDictionary dictionary] forKey:connectionName];
			}


			NSArray *dbs = [doc allDatabaseNames];
			NSArray *keys = [[schemaData objectForKey:connectionName] allKeys];
			for(id db in keys) {
				if(![dbs containsObject:[[db componentsSeparatedByString:SPUniqueSchemaDelimiter] objectAtIndex:1]]) {
					[[schemaData objectForKey:connectionName] removeObjectForKey:db];
				}
			}

			if([theConnection getDbStructure] && [[theConnection getDbStructure] objectForKey:connectionName]) {
				for(id item in [[[theConnection getDbStructure] objectForKey:connectionName] allKeys])
					[[schemaData objectForKey:connectionName] setObject:[[[theConnection getDbStructure] objectForKey:connectionName] objectForKey:item] forKey:item];
				[allSchemaKeys setObject:[theConnection getAllKeysOfDbStructure] forKey:connectionName];
			} else {

				if([theConnection serverMajorVersion] > 4) {
					[schemaData setObject:[NSDictionary dictionary] forKey:[NSString stringWithFormat:@"%@&DEL&no data loaded yet", connectionName]];
					[allSchemaKeys setObject:[NSArray array] forKey:connectionName];
				} else {
					[schemaData setObject:[NSDictionary dictionary] forKey:[NSString stringWithFormat:@"%@&DEL&no data for this server version", connectionName]];
					[allSchemaKeys setObject:[NSArray array] forKey:connectionName];
				}

			}

		}

		[outlineSchema1 reloadData];
		[outlineSchema2 reloadData];

		[self restoreExpandStatus];
		[self restoreSelectedItems];
	}

	[self syncButtonAction:self];

	if(isFiltered)
		[self filterTree:self];
	

}

- (BOOL)schemaPathExistsForConnection:(NSString*)connectionID andDatabase:(NSString*)dbname
{
	NSString *db_id = [NSString stringWithFormat:@"%@%@%@", connectionID, SPUniqueSchemaDelimiter, dbname];

	if([[[schemaData objectForKey:connectionID] allKeys] containsObject:db_id] 
		&& [[[schemaData objectForKey:connectionID] objectForKey:db_id] isKindOfClass:[NSDictionary class]]
		&& [[[schemaData objectForKey:connectionID] objectForKey:db_id] count])
		return YES;

	return NO;
}

- (void)removeDatabase:(NSString*)db_id forConnectionID:(NSString*)connectionID
{
	[[schemaData objectForKey:connectionID] removeObjectForKey:db_id];
	[outlineSchema1 reloadData];
	[outlineSchema2 reloadData];
}

#pragma mark -
#pragma mark IBActions


- (IBAction)reloadAllStructures:(id)sender
{

	// Reset everything
	[searchField setStringValue:@""];
	[schemaDataFiltered removeAllObjects];
	[schemaData removeAllObjects];
	[allSchemaKeys removeAllObjects];
	[infoArray removeAllObjects];
	[expandStatus1 removeAllObjects];
	[expandStatus2 removeAllObjects];
	[outlineSchema1 reloadData];
	[outlineSchema2 reloadData];
	selectedKey1 = @"";
	selectedKey2 = @"";
	selectionViewPort1 = NSZeroRect;
	selectionViewPort2 = NSZeroRect;
	[syncButton setState:NSOffState];
	isFiltered = NO;

	if ([[[NSDocumentController sharedDocumentController] documents] count]) {
		for(id doc in [[NSDocumentController sharedDocumentController] documents]) {
			if(![[doc valueForKeyPath:@"mySQLConnection"] isConnected]) continue;
			[NSThread detachNewThreadSelector:@selector(queryDbStructureWithUserInfo:) toTarget:[doc valueForKeyPath:@"mySQLConnection"] withObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], @"forceUpdate", nil]];
		}
	}

}

- (IBAction)outlineViewAction:(id)sender
{
	
}

- (IBAction)filterTree:(id)sender
{
	NSString *pattern = [[[searchField stringValue] stringByReplacingOccurrencesOfString:@"." withString:SPUniqueSchemaDelimiter] lowercaseString];

	[self saveSelectedItems];

	id currentItem = [outlineSchema2 selectedItem];
	id parentObject = nil;
	if(isFiltered)
		parentObject = [outlineSchema2 parentForItem:currentItem] ? [outlineSchema2 parentForItem:currentItem] : schemaDataFiltered;
	else
		parentObject = [outlineSchema2 parentForItem:currentItem] ? [outlineSchema2 parentForItem:currentItem] : schemaData;

	NSString *connectionID = nil;
	if(parentObject && [[parentObject allKeys] count])
		connectionID = [[[[parentObject allKeys] objectAtIndex:0] componentsSeparatedByString:SPUniqueSchemaDelimiter] objectAtIndex:0];
	
	if((pattern && ![pattern length]) || !parentObject || ![[parentObject allKeys] count] || !connectionID || [connectionID length] < 2 || ![allSchemaKeys objectForKey:connectionID]) {
		isFiltered = NO;
		[searchField setStringValue:@""];
		[schemaDataFiltered removeAllObjects];
		[outlineSchema2 reloadData];
		[self restoreExpandStatus];
		[self restoreSelectedItems];
		return;
	}

	isFiltered = YES;

	[syncButton setState:NSOffState];

	NSMutableDictionary *structure = [NSMutableDictionary dictionary];
	[structure setObject:[NSMutableDictionary dictionary] forKey:connectionID];


	for(NSString* item in [allSchemaKeys objectForKey:connectionID]) {
		if([[item lowercaseString] rangeOfString:pattern].length) {

			NSArray *a = [item componentsSeparatedByString:SPUniqueSchemaDelimiter];

			NSString *db_id = [NSString stringWithFormat:@"%@%@%@", connectionID,SPUniqueSchemaDelimiter,[a objectAtIndex:1]];

			if(!a || [a count] < 2) continue;

			if(![[structure valueForKey:connectionID] valueForKey:db_id]) {
				[[structure valueForKey:connectionID] setObject:[NSMutableDictionary dictionary] forKey:db_id];
			}
			if([a count] > 2) {

				NSString *table_id = [NSString stringWithFormat:@"%@%@%@", db_id,SPUniqueSchemaDelimiter,[a objectAtIndex:2]];

				if(![[[structure valueForKey:connectionID] valueForKey:db_id] valueForKey:table_id]) {
					[[[structure valueForKey:connectionID] valueForKey:db_id] setObject:[NSMutableDictionary dictionary] forKey:table_id];
				}

				if([[[[schemaData objectForKey:connectionID] objectForKey:db_id] objectForKey:table_id] objectForKey:@"  struct_type  "])
					[[[[structure valueForKey:connectionID] valueForKey:db_id] valueForKey:table_id] setObject:
						[[[[schemaData objectForKey:connectionID] objectForKey:db_id] objectForKey:table_id] objectForKey:@"  struct_type  "] forKey:@"  struct_type  "];
				else
					[[[[structure valueForKey:connectionID] valueForKey:db_id] valueForKey:table_id] setObject:
						[NSNumber numberWithInt:0] forKey:@"  struct_type  "];

				if([a count] > 3) {
					NSString *field_id = [NSString stringWithFormat:@"%@%@%@", table_id,SPUniqueSchemaDelimiter,[a objectAtIndex:3]];
					if([[[[schemaData objectForKey:connectionID] objectForKey:db_id] objectForKey:table_id] objectForKey:field_id])
						[[[[structure valueForKey:connectionID] valueForKey:db_id] valueForKey:table_id] setObject:
							[[[[schemaData objectForKey:connectionID] objectForKey:db_id] objectForKey:table_id] objectForKey:field_id] forKey:field_id];
				}
			}
			
		}
	}
	[outlineSchema1 reloadData];
	[schemaDataFiltered removeAllObjects];
	[outlineSchema2 reloadData];
	[schemaDataFiltered setDictionary:[structure retain]];
	[outlineSchema2 reloadData];
	[outlineSchema2 expandItem:[outlineSchema2 itemAtRow:0] expandChildren:YES];
}

- (IBAction)syncButtonAction:(id)sender
{

	if(!schemaData) return;

	if([syncButton state] == NSOnState) {

		if(isFiltered) {
			isFiltered = NO;
			[schemaDataFiltered removeAllObjects];
			[outlineSchema2 reloadData];
			[searchField setStringValue:@""];
		}

		if ([[[NSDocumentController sharedDocumentController] documents] count]) {
			TableDocument *doc = [[NSDocumentController sharedDocumentController] currentDocument];
			NSMutableString *key = [NSMutableString string];
			[key setString:[doc connectionID]];
			if([doc database] && [(NSString*)[doc database] length]){
				[key appendString:SPUniqueSchemaDelimiter];
				[key appendString:[doc database]];
			}
			if([doc table] && [(NSString*)[doc table] length]){
				[key appendString:SPUniqueSchemaDelimiter];
				[key appendString:[doc table]];
			}
			[self selectPath:key];
		}
	}
}

#pragma mark -
#pragma mark outline delegates

- (void)outlineViewItemDidExpand:(NSNotification *)notification
{
	SPNavigatorOutlineView *ov = [notification object];
	id item = [[notification userInfo] objectForKey:@"NSObject"];
	
	id parentObject = nil;
	if(isFiltered && ov == outlineSchema2)
		parentObject = [ov parentForItem:item] ? [ov parentForItem:item] : schemaDataFiltered;
	else
		parentObject = [ov parentForItem:item] ? [ov parentForItem:item] : schemaData;

	if(!parentObject || ![parentObject allKeysForObject:item] || ![[parentObject allKeysForObject:item] count]) return;

	if(ov == outlineSchema1)
	{
		[expandStatus1 setObject:@"" forKey:[[parentObject allKeysForObject:item] objectAtIndex:0]];
	}
	else if(ov == outlineSchema2 && !isFiltered)
	{
		[expandStatus2 setObject:@"" forKey:[[parentObject allKeysForObject:item] objectAtIndex:0]];
	}
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
	SPNavigatorOutlineView *ov = [notification object];
	id item = [[notification userInfo] objectForKey:@"NSObject"];
	
	id parentObject = nil;
	if(isFiltered && ov == outlineSchema2)
		parentObject = [ov parentForItem:item] ? [ov parentForItem:item] : schemaDataFiltered;
	else
		parentObject = [ov parentForItem:item] ? [ov parentForItem:item] : schemaData;
	
	if(!parentObject || ![parentObject allKeysForObject:item] || ![[parentObject allKeysForObject:item] count]) return;

	if(ov == outlineSchema1)
		[expandStatus1 removeObjectForKey:[[parentObject allKeysForObject:item] objectAtIndex:0]];
	else if(ov == outlineSchema2 && !isFiltered)
		[expandStatus2 removeObjectForKey:[[parentObject allKeysForObject:item] objectAtIndex:0]];
}

- (id)outlineView:(id)outlineView child:(NSInteger)index ofItem:(id)item
{

	if (item == nil) {
		if(isFiltered && outlineView == outlineSchema2)
			item = schemaDataFiltered;
		else
			item = schemaData;
	}

	if ([item isKindOfClass:[NSDictionary class]] && [item allKeys] && [[item allKeys] count]) {
		NSSortDescriptor *desc = [[NSSortDescriptor alloc] initWithKey:nil ascending:YES selector:@selector(localizedCompare:)];
		NSArray *sortedItems = [[item allKeys] sortedArrayUsingDescriptors:[NSArray arrayWithObject:desc]];
		[desc release];
		return [item objectForKey:[sortedItems objectAtIndex:index]];
	}
	else if ([item isKindOfClass:[NSArray class]]) 
	{
		return [item objectAtIndex:index];
	}
	return nil;
}

- (BOOL)outlineView:(id)outlineView isItemExpandable:(id)item
{
	if([item isKindOfClass:[NSDictionary class]] && [item count]) {
		// Suppress expanding for PROCEDUREs and FUNCTIONs
		if([item objectForKey:@"  struct_type  "] && [[item objectForKey:@"  struct_type  "] intValue] > 1) {
			return NO;
		}
		return YES;
	}
	
	return NO;
}

- (NSInteger)outlineView:(id)outlineView numberOfChildrenOfItem:(id)item
{

	if(isFiltered && outlineView == outlineSchema2) {
		if(item == nil)
			return [schemaDataFiltered count];
	} else {
		if(item == nil)
			return [schemaData count];
	}

	if([item isKindOfClass:[NSDictionary class]] || [item isKindOfClass:[NSArray class]])
		return [item count];

	return 0;
}

- (id)outlineView:(id)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{

	id parentObject = nil;

	if(outlineView == outlineSchema2 && isFiltered)
		parentObject = [outlineView parentForItem:item] ? [outlineView parentForItem:item] : schemaDataFiltered;
	else
		parentObject = [outlineView parentForItem:item] ? [outlineView parentForItem:item] : schemaData;

	if(!parentObject) return @"…";

	if ([[tableColumn identifier] isEqualToString:@"field"]) {

		// top level is connection
		if([outlineView levelForItem:item] == 0) {
			[[tableColumn dataCell] setImage:[NSImage imageNamed:@"network-small"]];
			if([parentObject allKeysForObject:item] && [[parentObject allKeysForObject:item] count]) {
				NSString *key = [[parentObject allKeysForObject:item] objectAtIndex:0];
				if([key rangeOfString:@"&SSH&"].length)
					return [[key componentsSeparatedByString:@"&SSH&"] objectAtIndex:0];
				else if([key rangeOfString:@"&DEL&"].length)
					return [[key componentsSeparatedByString:@"&DEL&"] objectAtIndex:0];
				else
					return key;
			} else {
				return @"";
			}
		}

		if ([parentObject isKindOfClass:[NSDictionary class]]) {
			if([item isKindOfClass:[NSDictionary class]]) {
				if([item objectForKey:@"  struct_type  "]) {

					NSInteger type = [[item objectForKey:@"  struct_type  "] intValue];
					switch(type) {
						case 0:
						[[tableColumn dataCell] setImage:[NSImage imageNamed:@"table-small-square"]];
						break;
						case 1:
						[[tableColumn dataCell] setImage:[NSImage imageNamed:@"table-view-small-square"]];
						break;
						case 2:
						[[tableColumn dataCell] setImage:[NSImage imageNamed:@"proc-small"]];
						break;
						case 3:
						[[tableColumn dataCell] setImage:[NSImage imageNamed:@"func-small"]];
						break;
					}
				} else {
					[[tableColumn dataCell] setImage:[NSImage imageNamed:@"database-small"]];
				}
				if([[parentObject allKeysForObject:item] count] == 1) {
					return [[[[parentObject allKeysForObject:item] objectAtIndex:0] componentsSeparatedByString:SPUniqueSchemaDelimiter] lastObject];
				} else {
					return @"…";
				}

			} else {
				if([[parentObject allKeysForObject:item] count]) {
					if([outlineView levelForItem:item] == 1) {
						// It's a db name which wasn't queried yet
						[[tableColumn dataCell] setImage:[NSImage imageNamed:@"database-small"]];
						return [[[[parentObject allKeysForObject:item] objectAtIndex:0] componentsSeparatedByString:SPUniqueSchemaDelimiter] lastObject];
					} else {
						// It's a field and use the key "  struct_type  " to increase the distance between node and first child
						if(![[[parentObject allKeysForObject:item] objectAtIndex:0] hasPrefix:@"  "]) {
							[[tableColumn dataCell] setImage:[NSImage imageNamed:@"field-small-square"]];
							return [[[[parentObject allKeysForObject:item] objectAtIndex:0] componentsSeparatedByString:SPUniqueSchemaDelimiter] lastObject];
						} else {
							[[tableColumn dataCell] setImage:[NSImage imageNamed:@"dummy-small"]];
							return nil;
						}
					}
				}
				return @"…";
			}
		}
		return [item description];
	}
	else if ([[tableColumn identifier] isEqualToString:@"type"]) {

		// top level is connection
		if([outlineView levelForItem:item] == 0) {
			if([parentObject allKeysForObject:item] && [[parentObject allKeysForObject:item] count]) {
				NSString *key = [[parentObject allKeysForObject:item] objectAtIndex:0];
				if([key rangeOfString:@"&SSH&"].length)
					return [NSString stringWithFormat:@"ssh: %@", [[[key componentsSeparatedByString:@"&SSH&"] lastObject]  stringByReplacingOccurrencesOfString:@"&DEL&" withString:@" - "]];
				else if([key rangeOfString:@"&DEL&"].length)
					return [[key componentsSeparatedByString:@"&DEL&"] lastObject];
				else
					return @"";
			} else {
				return @"";
			}
		}

		if ([item isKindOfClass:[NSArray class]] && [item count]>5 && [[parentObject allKeysForObject:item] count] && ![[[parentObject allKeysForObject:item] objectAtIndex:0] hasPrefix:@"  "]) 
		{
			NSString *typ = [NSString stringWithFormat:@"%@,%@,%@", [[item objectAtIndex:0] stringByReplacingOccurrencesOfRegex:@"\\(.*?,.*?\\)" withString:@"(…)"], [item objectAtIndex:3], [item objectAtIndex:5]]; 
			NSTokenFieldCell *b = [[[NSTokenFieldCell alloc] initTextCell:typ] autorelease];
			[b setEditable:NO];
			[b setAlignment:NSRightTextAlignment];
			[b setFont:[NSFont systemFontOfSize:11]];
			[b setDelegate:self];
			[b setWraps:NO];
			return b;
		}
		return nil;
	}

	return nil;
}

- (BOOL)outlineView:outlineView isGroupItem:(id)item
{
	if ([item isKindOfClass:[NSDictionary class]] || [outlineView levelForItem:item] == 1)
		return YES;
		
	return NO;
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item
{
	id parentObject = nil;

	if(outlineView == outlineSchema2 && isFiltered)
		parentObject = [outlineView parentForItem:item] ? [outlineView parentForItem:item] : schemaDataFiltered;
	else
		parentObject = [outlineView parentForItem:item] ? [outlineView parentForItem:item] : schemaData;

	if(!parentObject) return 0;

	// Use "  struct_type  " as placeholder to increase distance between table and first field name otherwise it looks ugly 
	if([parentObject allKeysForObject:item] && [[parentObject allKeysForObject:item] count] && [[[parentObject allKeysForObject:item] objectAtIndex:0] hasPrefix:@"  "])
		return 5.0;

	return 18.0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(id)item
{
	return YES;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	id parentObject = nil;

	if(outlineView == outlineSchema2 && isFiltered)
		parentObject = [outlineView parentForItem:item] ? [outlineView parentForItem:item] : schemaDataFiltered;
	else
		parentObject = [outlineView parentForItem:item] ? [outlineView parentForItem:item] : schemaData;

	if(!parentObject) return NO;

	if([parentObject allKeysForObject:item] && [[parentObject allKeysForObject:item] count] && [[[parentObject allKeysForObject:item] objectAtIndex:0] hasPrefix:@"  "])
		return NO;
	return YES;
}
/*
 * Double-click on item selects the chosen path in active connection window
 */
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	[self selectInActiveDocumentItem:item fromView:outlineView];
	return NO;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)aNotification
{

	id selectedItem = [[aNotification object] selectedItem];

	if(selectedItem) {
		[infoArray removeAllObjects];
		// First object is used as dummy to increase the distance between first item and header
		[infoArray addObject:@""];

		// selected item is a field
		if([selectedItem isKindOfClass:[NSArray class]]) {
			NSInteger i = 0;
			for(id item in selectedItem) {
				if([item isKindOfClass:[NSString class]] && [(NSString*)item length]) {
					[infoArray addObject:[NSString stringWithFormat:@"%@: %@", [self tableInfoLabelForIndex:i ofType:0], [item stringByReplacingOccurrencesOfString:@"," withString:@", "]]];
				}
				i++;
			}
		}

		// check if selected item is a PROCEDURE or FUNCTION
		else if([selectedItem isKindOfClass:[NSDictionary class]] && [selectedItem objectForKey:@"  struct_type  "] && [[selectedItem objectForKey:@"  struct_type  "] intValue] > 1) {
			NSInteger i = 0;
			NSInteger type = [[selectedItem objectForKey:@"  struct_type  "] intValue];
			NSArray *keys = [selectedItem allKeys];
			NSInteger keyIndex = 0;
			if(keys && [keys count] == 2) {
				// there only are two keys, get that key which doesn't begin with "  " due to it's the struct_type key
				if([[keys objectAtIndex:keyIndex] hasPrefix:@"  "]) keyIndex++;
				if([keys objectAtIndex:keyIndex] && [[selectedItem objectForKey:[keys objectAtIndex:keyIndex]] isKindOfClass:[NSArray class]]) {
					for(id item in [selectedItem objectForKey:[keys objectAtIndex:keyIndex]]) {
						if([item isKindOfClass:[NSString class]] && [(NSString*)item length]) {
							[infoArray addObject:[NSString stringWithFormat:@"%@: %@", [self tableInfoLabelForIndex:i ofType:type], item]];
						}
						i++;
					}
				}
			}
		}
	}
	[infoTable reloadData];
}

- (void)outlineView:(NSOutlineView *)outlineView didClickTableColumn:(NSTableColumn *)tableColumn
{
	if(outlineView == outlineSchema1) {
		[infoQuickAccessSplitView setPosition:0 ofDividerAtIndex:0];
		[schemaStatusSplitView setPosition:1000 ofDividerAtIndex:0];
		[schema12SplitView setPosition:1000 ofDividerAtIndex:0];
	} else if(outlineView == outlineSchema2) {
		[infoQuickAccessSplitView setPosition:0 ofDividerAtIndex:0];
		[schemaStatusSplitView setPosition:1000 ofDividerAtIndex:0];
		[schema12SplitView setPosition:0 ofDividerAtIndex:0];
	}
}

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{
	// Provide data for our custom type, and simple NSStrings.
	[pboard declareTypes:[NSArray arrayWithObjects:DragFromNavigatorPboardType, NSStringPboardType, nil] owner:self];

	// Collect the actual schema paths without leading connection ID
	NSMutableArray *draggedItems = [NSMutableArray array];
	for(id item in items) {
		id parentObject = [outlineView parentForItem:item] ? [outlineView parentForItem:item] : schemaData;
		if(!parentObject) return NO;
		id parentKeys = [parentObject allKeysForObject:item];
		if(parentKeys && [parentKeys count] == 1)
			[draggedItems addObject:[[[parentKeys objectAtIndex:0] description] stringByReplacingOccurrencesOfRegex:[NSString stringWithFormat:@"^.*?%@", SPUniqueSchemaDelimiter] withString:@""]];
	}

	// Drag the array with schema paths
	NSMutableData *arraydata = [[[NSMutableData alloc] init] autorelease];
	NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initForWritingWithMutableData:arraydata] autorelease];
	[archiver encodeObject:draggedItems forKey:@"itemdata"];
	[archiver finishEncoding];
	[pboard setData:arraydata forType:DragFromNavigatorPboardType];

	// For external destinations provide a comma separated string
	NSMutableString *dragString = [NSMutableString string];
	for(id item in draggedItems) {
		if([dragString length]) [dragString appendString:@", "];
		[dragString appendString:[[item componentsSeparatedByString:SPUniqueSchemaDelimiter] componentsJoinedByPeriodAndBacktickQuotedAndIgnoreFirst]];
	}

	if(![dragString length]) return NO;

	[pboard setString:dragString forType:NSStringPboardType];
	return YES;
}

#pragma mark -
#pragma mark table delegates

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	if(aTableView == infoTable && infoArray)
		return [infoArray count];

	return 0;

}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	// Use first row as dummy to increase the distance between content and header
	return (row == 0) ? 5.0 : 16.0;
}

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{
	if(aTableView == infoTable && infoArray)
		return NO;
		
	return YES;
}


- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if(aTableView == infoTable) {
		if(rowIndex == 0) {
			[(ImageAndTextCell*)aCell setImage:[NSImage imageNamed:@"dummy-small"]];
			[(ImageAndTextCell*)aCell setIndentationLevel:0];
			[(ImageAndTextCell*)aCell setDrawsBackground:NO];
		} else {
			[(ImageAndTextCell*)aCell setImage:[NSImage imageNamed:@"table-property"]];
			[(ImageAndTextCell*)aCell setIndentationLevel:1];
			[(ImageAndTextCell*)aCell setDrawsBackground:NO];
		}
	}
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if(aTableView == infoTable && infoArray && rowIndex < [infoArray count]) {
		return [infoArray objectAtIndex:rowIndex];
	}

	return nil;
}

- (void)tableView:(NSTableView*)tableView didClickTableColumn:(NSTableColumn *)tableColumn
{

	if(tableView == infoTable || tableView == quickAccessTable) {
		[infoQuickAccessSplitView setPosition:1000 ofDividerAtIndex:0];
		[schemaStatusSplitView setPosition:200 ofDividerAtIndex:0];
		[outlineSchema1 scrollRowToVisible:[outlineSchema1 selectedRow]];
		[outlineSchema2 scrollRowToVisible:[outlineSchema2 selectedRow]];
	}
}

#pragma mark -
#pragma mark others

- (NSString*)tableInfoLabelForIndex:(NSInteger)index ofType:(NSInteger)type
{

	if(type == 0 || type == 1) // TABLE / VIEW
		switch(index) {
			case 0:
			return NSLocalizedString(@"Type", @"type label");
			case 1:
			return NSLocalizedString(@"Default", @"default label");
			case 2:
			return NSLocalizedString(@"Is Nullable", @"is nullable label");
			case 3:
			return NSLocalizedString(@"Encoding", @"encoding label");
			case 4:
			return NSLocalizedString(@"Collation", @"collation label");
			case 5:
			return NSLocalizedString(@"Key", @"key label");
			case 6:
			return NSLocalizedString(@"Extra", @"extra label");
			case 7:
			return NSLocalizedString(@"Privileges", @"privileges label");
			case 8:
			return NSLocalizedString(@"Comment", @"comment label");
		}

	if(type == 2) // PROCEDURE
		switch(index) {
			case 0:
			return @"DTD Identifier";
			case 1:
			return NSLocalizedString(@"Default", @"default label");
			case 2:
			return @"SQL Data Access";
			case 3:
			return NSLocalizedString(@"Encoding", @"encoding label");
			case 4:
			return NSLocalizedString(@"Collation", @"collation label");
			case 5:
			return @"Is Deterministic";
			case 6:
			return @"Security Type";
			case 7:
			return @"Definer";
			case 8:
			return NSLocalizedString(@"Comment", @"comment label");
		}
	if(type == 3) // FUNCTION
		switch(index) {
			case 0:
			return NSLocalizedString(@"Return Type", @"return type label");
			case 1:
			return NSLocalizedString(@"Default", @"default label");
			case 2:
			return @"SQL Data Access";
			case 3:
			return NSLocalizedString(@"Encoding", @"encoding label");
			case 4:
			return NSLocalizedString(@"Collation", @"collation label");
			case 5:
			return @"Is Deterministic";
			case 6:
			return NSLocalizedString(@"Execution Privilege", @"execution privilege label");
			case 7:
			return @"Definer";
			case 8:
			return NSLocalizedString(@"Comment", @"comment label");
		}
	return @"";
}
@end