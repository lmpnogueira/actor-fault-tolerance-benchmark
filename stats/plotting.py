import os
from enum import Enum
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns


# ---------------------------------------------------------------------------
# Data filtering
# ---------------------------------------------------------------------------

def load_and_filter_data(df: pd.DataFrame, **filters) -> pd.DataFrame:
    """
    Return a filtered copy of df, keeping rows that match the given filters.

    Each kwarg is a column name:
      - if value is a list: keep rows whose column value is in the list.
      - if value is a single value: keep rows equal to that value.
      - if value is None or empty list: skip that filter.
    """
    df_filtered = df.copy()
    for key, value in filters.items():
        if value is None or value == []:
            continue
        if isinstance(value, list):
            df_filtered = df_filtered[df_filtered[key].isin(value)]
        else:
            df_filtered = df_filtered[df_filtered[key] == value]
    return df_filtered


# ---------------------------------------------------------------------------
# Plotting
# ---------------------------------------------------------------------------

def plot_data(
        df: pd.DataFrame,
        plot_type: str = 'line',
        stat: str = 'median',
        x_axis: str = 'init_timestamp',
        y_desc: str = '',
        x_desc: str = '',
        title: str = '',
        save_path: str = None
) -> None:
    """
    Plot the filtered DataFrame.

    plot_type: 'line' or 'box'
    stat: which statistic column to plot (must exist in df)
    x_axis: column name for x-axis
    y_desc, x_desc, title: axis labels and plot title
    """
    sns.set_theme(style="whitegrid")
    plt.style.use('default')  # Reset to default style

    stat_column_map = {
        'mean': 'mean',
        'median': 'median',
        'min': 'min',
        'max': 'max',
        'perc_full': 'perc_full',
        'perc_none': 'perc_none',
    }

    language_palette = {
        'elixir': '#510c8c',
        'scala': '#b50d22',
        'go-protoactor': '#0ca0c7',
    }

    if df.empty:
        print("No data to plot.")
        return

    y_col = stat_column_map.get(stat)
    if y_col not in df.columns:
        print(f"Statistic column '{y_col}' not found.")
        return

    plt.figure(figsize=(10, 6), facecolor='white')

    if plot_type == 'line':
        df_sorted = df.sort_values(by=x_axis)
        sns.lineplot(
            data=df_sorted,
            x=x_axis,
            y=y_col,
            hue='lang',
            marker='o',
            palette=language_palette
        )
        plt.title(title)
        plt.xlabel(x_desc)
        plt.ylabel(y_desc)
        plt.legend(title='Language')

        if pd.api.types.is_numeric_dtype(df_sorted[x_axis]):
            plt.xticks(rotation=0)
        else:
            plt.xticks(rotation=45)

    elif plot_type == 'box':
        fig, ax = plt.subplots(figsize=(10, 6))

        x_values = sorted(df[x_axis].unique())
        languages = sorted(df['lang'].unique())

        box_data = []
        positions = []
        width = 0.8 / len(languages)
        color_map = []

        for i, x_val in enumerate(x_values):
            for j, lang in enumerate(languages):
                subset = df[(df[x_axis] == x_val) & (df['lang'] == lang)]
                if not subset.empty:
                    row = subset.iloc[0]
                    box = {
                        'med': row['median'],
                        'q1': row['q1'],
                        'q3': row['q3'],
                        'whislo': row['min'],
                        'whishi': row['max'],
                        'fliers': [],
                        'mean': row['mean'],
                        'caplo': row['min'],
                        'caphi': row['max'],
                    }
                    box_data.append(box)
                    pos = i - 1 + j * width + width / 2
                    positions.append(pos)
                    color_map.append(language_palette.get(lang, '#cccccc'))

        bplot = ax.bxp(box_data, positions=positions, widths=width,
                       showmeans=False, patch_artist=True)

        for patch, color in zip(bplot['boxes'], color_map):
            patch.set_facecolor(color)

        ax.set_xticks(range(len(x_values)))
        ax.set_xticklabels([str(x) for x in x_values])
        ax.set_xlabel(x_desc)
        ax.set_ylabel(y_desc)
        ax.set_title(title)

        handles = [plt.Rectangle((0, 0), 1, 1, color=language_palette[lang])
                   for lang in languages]
        ax.legend(handles, languages, title='Language')

        plt.xticks(rotation=45)

    else:
        print("Invalid plot type. Use 'line' or 'box'.")
        return

    plt.tight_layout()
    if save_path:
        os.makedirs(os.path.dirname(os.path.abspath(save_path)), exist_ok=True)
        plt.savefig(save_path, dpi=200, bbox_inches='tight')
        print(f"Figure saved to {save_path}")
        plt.close()
    else:
        plt.show()


# ---------------------------------------------------------------------------
# Enum for test type
# ---------------------------------------------------------------------------

class TestType(Enum):
    THROUGHPUT = 1
    RECONNECTION = 2
    DETECTION = 3


def load_results(test_type: TestType, results_dir: str = './results') -> pd.DataFrame:
    """
    Load the appropriate CSV file based on the test type.
    """
    if test_type == TestType.THROUGHPUT:
        path = os.path.join(results_dir, 'throughput_computed.csv')
    elif test_type == TestType.RECONNECTION:
        path = os.path.join(results_dir, 'reconnection_computed.csv')
    else:
        path = os.path.join(results_dir, 'detection_computed.csv')
    return pd.read_csv(path)


if __name__ == "__main__":
    # Choose the experiment type
    test_type = TestType.THROUGHPUT  # or TestType.THROUGHPUT, TestType.DETECTION, TestType.RECONNECTION

    # Filters to apply to the dataframe
    filters = {
        'lang': ['go-protoactor', 'elixir', 'scala'], # scala, elixir, go-protoactor
        'num_supervisor': 1,
        'chats_per_sup': 256,
        'fault_type': 'error',
        'clients_per_server': 5,
        # 'fault_pause': 5000,
    }

    df = load_results(test_type)
    filtered_df = load_and_filter_data(df, **filters)

    plot_data(
        df=filtered_df,
        plot_type='box',
        stat='mean',
        x_axis='fault_pause',
        y_desc='Throughput (messages / second)',
        x_desc='Transient Fault Injection Time (ms)',
        title='Throughput capacity - 256 chats with 5 clients on each',
        save_path='./results/figures/throughput_256chats_5clients.png'
    )
