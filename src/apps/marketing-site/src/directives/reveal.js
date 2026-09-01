function prefersReducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

export const vReveal = {
  mounted(el, binding) {
    el.classList.add('reveal');

    const delay = Number(binding.value?.delay ?? binding.value ?? 0);
    if (delay) {
      el.style.setProperty('--reveal-delay', `${delay}ms`);
    }

    if (prefersReducedMotion()) {
      el.classList.add('is-visible');
      return;
    }

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        el.classList.add('is-visible');
        observer.disconnect();
      },
      { threshold: 0.12, rootMargin: '0px 0px -48px 0px' },
    );

    observer.observe(el);
    el._revealObserver = observer;
  },
  unmounted(el) {
    el._revealObserver?.disconnect();
  },
};
