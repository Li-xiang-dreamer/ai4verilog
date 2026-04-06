import argparse
from pathlib import Path

import cv2
import matplotlib.pyplot as plt
import numpy as np


def load_txt_image(file_path: str, delimiter: str = None) -> np.ndarray:
    """Load an infrared grayscale image matrix from a txt file."""
    image = np.loadtxt(file_path, delimiter=delimiter)
    if image.ndim != 2:
        raise ValueError("Input txt file must contain a 2D grayscale matrix.")
    return image.astype(np.float32)


def normalize_to_unit(image: np.ndarray) -> np.ndarray:
    """Normalize image to [0, 1] while handling constant matrices safely."""
    min_val = float(image.min())
    max_val = float(image.max())
    if max_val - min_val < 1e-8:
        return np.zeros_like(image, dtype=np.float32)
    return ((image - min_val) / (max_val - min_val)).astype(np.float32)


def preprocess_image(
    image: np.ndarray,
    use_bilateral: bool = True,
    gaussian_kernel: int = 5,
    bilateral_d: int = 7,
    bilateral_sigma_color: float = 0.08,
    bilateral_sigma_space: float = 7.0,
) -> np.ndarray:
    """
    Preprocess image with normalization and optional denoising.

    The image is kept in float32 [0, 1] format for numerically stable filtering.
    """
    normalized = normalize_to_unit(image)
    smoothed = cv2.GaussianBlur(normalized, (gaussian_kernel, gaussian_kernel), 0)

    if not use_bilateral:
        return smoothed

    return cv2.bilateralFilter(
        smoothed,
        d=bilateral_d,
        sigmaColor=bilateral_sigma_color,
        sigmaSpace=bilateral_sigma_space,
    )


def compute_edge_response(
    image: np.ndarray,
    sobel_weight: float = 0.5,
    scharr_weight: float = 0.3,
    laplacian_weight: float = 0.2,
) -> np.ndarray:
    """Fuse multiple derivative operators to obtain a robust edge response."""
    sobel_x = cv2.Sobel(image, cv2.CV_32F, 1, 0, ksize=3)
    sobel_y = cv2.Sobel(image, cv2.CV_32F, 0, 1, ksize=3)
    sobel_mag = cv2.magnitude(sobel_x, sobel_y)

    scharr_x = cv2.Scharr(image, cv2.CV_32F, 1, 0)
    scharr_y = cv2.Scharr(image, cv2.CV_32F, 0, 1)
    scharr_mag = cv2.magnitude(scharr_x, scharr_y)

    laplacian = cv2.Laplacian(image, cv2.CV_32F, ksize=3)
    laplacian_abs = np.abs(laplacian)

    fused = (
        sobel_weight * normalize_to_unit(sobel_mag)
        + scharr_weight * normalize_to_unit(scharr_mag)
        + laplacian_weight * normalize_to_unit(laplacian_abs)
    )
    return normalize_to_unit(fused)


def enhance_edges(
    image: np.ndarray,
    edge_response: np.ndarray,
    sharpen_amount: float = 1.1,
    edge_gain: float = 1.4,
    detail_sigma: float = 1.2,
) -> np.ndarray:
    """
    Enhance target contours using unsharp masking plus weighted edge injection.

    The mask is moderated by the edge response so that flat noisy regions are less amplified.
    """
    base_blur = cv2.GaussianBlur(image, (0, 0), detail_sigma)
    detail = image - base_blur
    guided_detail = detail * (0.35 + 0.65 * edge_response)
    enhanced = image + sharpen_amount * guided_detail + edge_gain * edge_response
    return np.clip(enhanced, 0.0, 1.0)


def to_uint8(image: np.ndarray) -> np.ndarray:
    """Convert normalized float image [0, 1] to uint8 for display or saving."""
    return np.clip(image * 255.0, 0, 255).astype(np.uint8)


def show_results(
    original: np.ndarray,
    preprocessed: np.ndarray,
    edge_response: np.ndarray,
    enhanced: np.ndarray,
    show: bool = True,
    figure_path: str = None,
) -> None:
    """Visualize the full processing pipeline."""
    fig, axes = plt.subplots(2, 2, figsize=(11, 9))
    images = [
        (original, "Original Image"),
        (preprocessed, "Preprocessed Image"),
        (edge_response, "Edge Response"),
        (enhanced, "Enhanced Image"),
    ]

    for ax, (image, title) in zip(axes.ravel(), images):
        ax.imshow(image, cmap="gray", vmin=0, vmax=1)
        ax.set_title(title)
        ax.axis("off")

    fig.suptitle("Infrared Image Edge Enhancement", fontsize=14)
    fig.tight_layout()
    if figure_path:
        fig.savefig(figure_path, dpi=150, bbox_inches="tight")
    if show:
        plt.show()
    plt.close(fig)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Enhance target edges in an infrared image stored as a txt matrix."
    )
    parser.add_argument("input_txt", type=str, help="Path to the txt matrix file.")
    parser.add_argument(
        "--delimiter",
        type=str,
        default=None,
        help="Delimiter used in the txt file, e.g. ',' or ' '. Default: auto by numpy.",
    )
    parser.add_argument(
        "--disable-bilateral",
        action="store_true",
        help="Disable bilateral filtering in preprocessing.",
    )
    parser.add_argument(
        "--save-dir",
        type=str,
        default=None,
        help="Optional output directory for saving intermediate and final images.",
    )
    parser.add_argument(
        "--no-show",
        action="store_true",
        help="Do not open the matplotlib window; useful for headless execution.",
    )
    return parser.parse_args()


def save_outputs(
    save_dir: str,
    original: np.ndarray,
    preprocessed: np.ndarray,
    edge_response: np.ndarray,
    enhanced: np.ndarray,
) -> None:
    output_dir = Path(save_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_dir / "original.png"), to_uint8(original))
    cv2.imwrite(str(output_dir / "preprocessed.png"), to_uint8(preprocessed))
    cv2.imwrite(str(output_dir / "edge_response.png"), to_uint8(edge_response))
    cv2.imwrite(str(output_dir / "enhanced.png"), to_uint8(enhanced))
    return str(output_dir / "pipeline_overview.png")


def main() -> None:
    args = parse_args()

    raw_image = load_txt_image(args.input_txt, args.delimiter)
    original = normalize_to_unit(raw_image)
    preprocessed = preprocess_image(
        raw_image,
        use_bilateral=not args.disable_bilateral,
    )
    edge_response = compute_edge_response(preprocessed)
    enhanced = enhance_edges(preprocessed, edge_response)

    figure_path = None
    if args.save_dir:
        figure_path = save_outputs(
            args.save_dir, original, preprocessed, edge_response, enhanced
        )

    show_results(
        original,
        preprocessed,
        edge_response,
        enhanced,
        show=not args.no_show,
        figure_path=figure_path,
    )


if __name__ == "__main__":
    main()
