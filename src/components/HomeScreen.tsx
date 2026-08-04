import { DOOR_INFO, type GameDoor } from '../game/modes';
import {
  DuelIcon,
  HelpIcon,
  PlayersIcon,
  SettingsIcon,
  SoloIcon,
  StatsIcon,
  TutorialIcon,
} from './icons';

interface HomeScreenProps {
  /** Head through one of the game doors. What happens next is the door's
   * business: Solo starts a game, the multiplayer pair open a lobby, and a
   * first-timer gets the tutorial before any of it. */
  onPlay: (door: GameDoor) => void;
  /** Start the guided tutorial. */
  onTutorial: () => void;
  onShowHowTo: () => void;
  onShowStats: () => void;
  onShowSettings: () => void;
}

/** The three doors, in the order they're offered. */
const DOORS: Array<{ door: GameDoor; icon: React.ReactNode }> = [
  { door: 'solo', icon: <SoloIcon /> },
  { door: 'survival', icon: <PlayersIcon /> },
  { door: 'duel', icon: <DuelIcon /> },
];

/** The utility grid's buttons: an icon over a label. */
function HomeAction({
  icon,
  label,
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
}) {
  return (
    <button type="button" className="btn home-action" onClick={onClick}>
      <span className="home-action-icon">{icon}</span>
      {label}
    </button>
  );
}

/**
 * The splash screen the app opens on: the game's name up top, then one column
 * of buttons — the modes, then the things that aren't a game. A mode button
 * says only what the mode is called; what it *is* gets explained once, in the
 * popover that fronts its first game, rather than sitting behind an ⓘ nobody
 * presses.
 *
 * The column stays a single column at every width: it keeps the buttons under
 * one another wherever the thumb already is, and a four-across row of huge
 * targets on a desktop looked like a toolbar rather than a choice.
 */
export function HomeScreen({
  onPlay,
  onTutorial,
  onShowHowTo,
  onShowStats,
  onShowSettings,
}: HomeScreenProps) {
  return (
    <div className="home">
      <div className="home-inner">
        <header className="home-header">
          <h1 className="home-title">Word</h1>
          <p className="home-tagline">Race to weave every tile into one crossword.</p>
        </header>

        <div className="home-modes">
          {DOORS.map(({ door, icon }) => (
            <button key={door} type="button" className="mode-card" onClick={() => onPlay(door)}>
              <span className="mode-card-icon">{icon}</span>
              <span className="mode-card-name">{DOOR_INFO[door].name}</span>
            </button>
          ))}
        </div>

        <div className="home-actions">
          <HomeAction icon={<TutorialIcon />} label="Tutorial" onClick={onTutorial} />
          <HomeAction icon={<HelpIcon />} label="How to play" onClick={onShowHowTo} />
          <HomeAction icon={<StatsIcon />} label="Stats" onClick={onShowStats} />
          <HomeAction icon={<SettingsIcon />} label="Settings" onClick={onShowSettings} />
        </div>
      </div>
    </div>
  );
}
